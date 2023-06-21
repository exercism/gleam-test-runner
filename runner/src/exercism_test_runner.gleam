import gleam/io
import gleam/list
import gleam/bool
import gleam/result
import gleam/string
import gleam/bit_string
import gleam/dynamic.{Dynamic}
import gleam/erlang/atom.{Atom}
import gleam/erlang/charlist.{Charlist}
import simplifile
import glance

pub fn main() {
  let assert Ok(files) = read_directory("test")
  let suites = list.map(files, read_module)
  list.map(suites, run_suite)
}

fn run_suite(suite: Suite) -> Nil {
  list.map(suite.tests, run_test)
  Nil
}

fn run_test(test: Test) -> Nil {
  io.print(test.name <> ": ")
  case test.function() {
    Ok(_) -> io.println("ok")
    Error(error) -> {
      io.print("\n\t")
      io.debug(error)
      Nil
    }
  }
}

pub type Error {
  Unequal(Dynamic, Dynamic)
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
  let function = fn() {
    apply(module, atom.create_from_string(name), [])
    Ok(Nil)
  }
  Ok(Test(name: name, src: src, function: function))
}

type Suite {
  Suite(name: String, path: String, tests: List(Test))
}

type Test {
  Test(name: String, function: fn() -> Result(Nil, Error), src: String)
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
