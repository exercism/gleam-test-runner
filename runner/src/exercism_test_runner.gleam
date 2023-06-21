import gleam/io
import gleam/list
import gleam/bool
import gleam/result
import gleam/string
import gleam/option.{None, Option, Some}
import gleam/bit_string
import gleam/dynamic.{Dynamic}
import gleam/erlang
import gleam/erlang/atom.{Atom}
import gleam/erlang/charlist.{Charlist}
import simplifile
import glance

// {
//   "version": 2,
//   "status": "pass" | "fail" | "error",
//   "message": "required if status is error",
//   "tests": [
//     {
//       "name": "test name",
//       "test_code": "assert 1 == 1",
//       "status": "pass" | "fail" | "error",
//       "message": "required if status is error or fail",
//       "output": "output printed by the user",
//     }
//   ]
// }

pub fn main() {
  let assert Ok(files) = read_directory("test")
  let suites = list.map(files, read_module)
  let _results = list.flat_map(suites, run_suite)
  Nil
}

fn run_suite(suite: Suite) -> List(TestResult) {
  list.map(suite.tests, run_test)
}

fn run_test(test: Test) -> TestResult {
  io.print(test.name <> ": ")
  let error = case test.function() {
    Ok(_) -> {
      io.println("ok")
      None
    }
    Error(error) -> {
      print_error(error)
      Some(error)
    }
  }
  TestResult(name: test.name, error: error, output: "")
}

fn print_error(error: Error) -> Nil {
  case error {
    Unequal(expected, actual) -> {
      io.println("left != right")
      io.println("   left: " <> string.inspect(expected))
      io.println("  right: " <> string.inspect(actual))
    }
    PatternMatchFailed(value) -> {
      io.println("Pattern match failed")
      io.println("  unexpected value: " <> string.inspect(value))
    }
    Crashed(message) -> {
      io.print("  Crashed with error: ")
      io.println(message)
    }
  }
  Nil
}

pub type Error {
  Unequal(left: Dynamic, right: Dynamic)
  PatternMatchFailed(value: Dynamic)
  Crashed(String)
}

external fn read_directory(String) -> Result(List(Charlist), Dynamic) =
  "file" "list_dir"

type BeamModule

external fn atom_to_module(Atom) -> BeamModule =
  "gleam_stdlib" "identity"

/// This function is unsafe. It does not verify that the atom is a BEAM module
/// currently loaded by the VM, or that the function exists. Don't mess up!
external fn apply(BeamModule, Atom, List(Dynamic)) -> Dynamic =
  "erlang" "apply"

fn read_module(filename: Charlist) -> Suite {
  let filename = charlist.to_string(filename)
  let name = string.drop_right(filename, 6)
  let path = "test/" <> filename
  let assert Ok(src) = simplifile.read(path)
  let assert Ok(ast) = glance.module(src)
  let module = get_beam_module(name)
  let tests = list.filter_map(ast.functions, get_test(src, module, _))
  Suite(name: name, path: path, tests: tests)
}

/// This function is unsafe. It does not verify that the atom is a BEAM module
/// currently loaded by the VM. Don't mess up!
fn get_beam_module(name: String) -> BeamModule {
  let assert Ok(atom) =
    name
    |> string.replace("/", "@")
    |> atom.from_string
  atom_to_module(atom)
}

fn get_test(
  src: String,
  module: BeamModule,
  function: glance.Definition(glance.Function),
) -> Result(Test, Nil) {
  let glance.Function(name: name, location: glance.Span(start, end), ..) =
    function.definition

  // If it doesn't end with _test then it's not a test
  use <- bool.guard(!string.ends_with(name, "_test"), Error(Nil))

  let src = extract_function_body(src, start, end)
  let function = fn() { run_test_function(module, name) }
  Ok(Test(name: name, src: src, function: function))
}

fn run_test_function(module: BeamModule, name: String) -> Result(Nil, Error) {
  fn() { apply(module, atom.create_from_string(name), []) }
  |> erlang.rescue
  |> result.map_error(convert_error)
  |> result.replace(Nil)
}

fn convert_error(error: erlang.Crash) -> Error {
  case error {
    erlang.Exited(error) -> Crashed(string.inspect(error))
    erlang.Thrown(error) -> Crashed(string.inspect(error))
    erlang.Errored(error) ->
      decode_unequal_error(error)
      |> result.or(decode_pattern_match_failed_error(error))
      |> result.unwrap(Crashed(string.inspect(error)))
  }
}

fn decode_pattern_match_failed_error(
  error: Dynamic,
) -> Result(Error, dynamic.DecodeErrors) {
  let decoder =
    dynamic.decode2(
      fn(_, a) { PatternMatchFailed(a) },
      dynamic.field(
        atom.create_from_string("message"),
        decode_tag("Assertion pattern match failed", _),
      ),
      dynamic.field(atom.create_from_string("value"), Ok),
    )
  decoder(error)
}

fn decode_unequal_error(error: Dynamic) -> Result(Error, dynamic.DecodeErrors) {
  let tag = atom.create_from_string("unequal")
  let decoder =
    dynamic.decode3(
      fn(_, a, b) { Unequal(a, b) },
      dynamic.element(0, decode_tag(tag, _)),
      dynamic.element(1, Ok),
      dynamic.element(2, Ok),
    )
  decoder(error)
}

fn decode_tag(tag: anything, data: Dynamic) -> Result(Nil, dynamic.DecodeErrors) {
  case dynamic.from(tag) == data {
    True -> Ok(Nil)
    False -> Error([dynamic.DecodeError("Tag", dynamic.classify(data), [])])
  }
}

type Suite {
  Suite(name: String, path: String, tests: List(Test))
}

type Test {
  Test(name: String, function: fn() -> Result(Nil, Error), src: String)
}

type TestResult {
  TestResult(name: String, error: Option(Error), output: String)
}

pub fn extract_function_body(src: String, start: Int, end: Int) -> String {
  src
  |> bit_string.from_string
  |> bit_string.slice(start, end - start)
  |> result.unwrap(<<>>)
  |> bit_string.to_string
  |> result.unwrap("")
  |> string.drop_right(1)
  |> drop_function_header
  |> string.trim
  |> string.split("\n")
  |> list.map(undent)
  |> string.join("\n")
}

fn drop_function_header(src: String) -> String {
  case string.pop_grapheme(src) {
    Ok(#("{", src)) -> src
    Ok(#(_, src)) -> drop_function_header(src)
    Error(_) -> src
  }
}

fn undent(line: String) -> String {
  case string.starts_with(line, "  ") {
    True -> string.drop_left(line, 2)
    False -> line
  }
}
