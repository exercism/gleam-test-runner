// TODO: Get and show stacktrace
// TODO: Collect output.
// - https://github.com/JohnBjrk/showtime/blob/e09519075a66fce96ae1a75e91d696dae5cff652/src/showtime_ffi.erl#LL5C1-L38C9
// TODO: Write results json file
// TODO: Tests for formatting, test running, etc
import gleam/io
import gleam/int
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
  let results = list.flat_map(suites, run_suite)
  let #(passed, message) = print_summary(results)
  io.println(message)
  halt(case passed {
    True -> 0
    False -> 1
  })
}

fn run_suite(suite: Suite) -> List(TestResult) {
  list.map(suite.tests, run_test)
}

fn run_test(test: Test) -> TestResult {
  let error = case test.function() {
    Ok(_) -> {
      io.print(".")
      None
    }
    Error(error) -> {
      io.println("F")
      io.println(print_error(test, error))
      Some(error)
    }
  }
  TestResult(name: test.name, error: error, output: "")
}

fn print_error(test: Test, error: Error) -> String {
  case error {
    Unequal(expected, actual) -> {
      string.join(
        [
          "   file: " <> test.module_path,
          "   test: " <> test.name,
          "message: left != right",
          "   left: " <> string.inspect(expected),
          "  right: " <> string.inspect(actual),
        ],
        "\n",
      )
    }
    Todo(message) -> {
      string.join(
        [
          "   file: " <> test.module_path,
          "   test: " <> test.name,
          "message: " <> message,
        ],
        "\n",
      )
    }
    Panic(message) -> {
      string.join(
        [
          "   file: " <> test.module_path,
          "   test: " <> test.name,
          "message: " <> message,
        ],
        "\n",
      )
    }
    Unmatched(value, line) -> {
      string.join(
        [
          "   file: " <> test.module_path <> ":" <> int.to_string(line),
          "   test: " <> test.name,
          "message: Pattern match failed",
          "  value: " <> string.inspect(value),
        ],
        "\n",
      )
    }
    UnmatchedCase(value) -> {
      string.join(
        [
          "   file: " <> test.module_path,
          "   test: " <> test.name,
          "message: Pattern match failed",
          "  value: " <> string.inspect(value),
        ],
        "\n",
      )
    }
    Crashed(error) -> {
      string.join(
        [
          "   file: " <> test.module_path,
          "   test: " <> test.name,
          "message: Program crashed",
          "  error: " <> string.inspect(error),
        ],
        "\n",
      )
    }
  }
}

fn print_summary(results: List(TestResult)) -> #(Bool, String) {
  let total =
    results
    |> list.length
    |> int.to_string
  let failed =
    results
    |> list.filter(fn(result) { result.error != None })
    |> list.length
    |> int.to_string
  let message = "\nRan " <> total <> " tests, " <> failed <> " failures"
  #(failed == "0", message)
}

pub type Error {
  Unequal(left: Dynamic, right: Dynamic)
  Todo(message: String)
  Panic(message: String)
  Unmatched(value: Dynamic, line: Int)
  UnmatchedCase(value: Dynamic)
  Crashed(error: Dynamic)
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
  let tests = list.filter_map(ast.functions, get_test(src, path, module, _))
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
  module_path: String,
  module: BeamModule,
  function: glance.Definition(glance.Function),
) -> Result(Test, Nil) {
  let glance.Function(name: name, location: glance.Span(start, end), ..) =
    function.definition

  // If it doesn't end with _test then it's not a test
  use <- bool.guard(!string.ends_with(name, "_test"), Error(Nil))

  let src = extract_function_body(src, start, end)
  let function = fn() { run_test_function(module, name) }
  Ok(Test(name: name, src: src, module_path: module_path, function: function))
}

fn run_test_function(module: BeamModule, name: String) -> Result(Nil, Error) {
  fn() { apply(module, atom.create_from_string(name), []) }
  |> erlang.rescue
  |> result.map_error(convert_error)
  |> result.replace(Nil)
}

fn convert_error(error: erlang.Crash) -> Error {
  case error {
    erlang.Exited(error) -> Crashed(error)
    erlang.Thrown(error) -> Crashed(error)
    erlang.Errored(error) -> {
      let decoders = [
        decode_unequal_error,
        decode_pattern_match_failed_error,
        decode_case_clause_error,
        decode_todo_error,
        decode_panic_error,
      ]
      error
      |> dynamic.any(decoders)
      |> result.unwrap(Crashed(error))
    }
  }
}

fn decode_pattern_match_failed_error(
  error: Dynamic,
) -> Result(Error, dynamic.DecodeErrors) {
  let decoder =
    dynamic.decode3(
      fn(_, value, line) { Unmatched(value, line) },
      dynamic.field(
        atom.create_from_string("gleam_error"),
        decode_tag("Assertion pattern match failed", _),
      ),
      dynamic.field(atom.create_from_string("value"), Ok),
      dynamic.field(atom.create_from_string("line"), dynamic.int),
    )
  decoder(error)
}

fn decode_todo_error(error: Dynamic) -> Result(Error, dynamic.DecodeErrors) {
  let decoder =
    dynamic.decode2(
      fn(_, message) { Todo(message) },
      dynamic.field(
        atom.create_from_string("gleam_error"),
        decode_tag(atom.create_from_string("todo"), _),
      ),
      dynamic.field(atom.create_from_string("message"), dynamic.string),
    )
  decoder(error)
}

fn decode_panic_error(error: Dynamic) -> Result(Error, dynamic.DecodeErrors) {
  let decoder =
    dynamic.decode2(
      fn(_, message) { Panic(message) },
      dynamic.field(
        atom.create_from_string("gleam_error"),
        decode_tag(atom.create_from_string("panic"), _),
      ),
      dynamic.field(atom.create_from_string("message"), dynamic.string),
    )
  decoder(error)
}

fn decode_case_clause_error(
  error: Dynamic,
) -> Result(Error, dynamic.DecodeErrors) {
  let decoder =
    dynamic.decode2(
      fn(_, value) { UnmatchedCase(value) },
      dynamic.element(0, decode_tag(atom.create_from_string("case_clause"), _)),
      dynamic.element(1, Ok),
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
  Test(
    name: String,
    module_path: String,
    function: fn() -> Result(Nil, Error),
    src: String,
  )
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

external fn halt(Int) -> a =
  "erlang" "halt"
