// TODO: Get and show stacktrace
// TODO: Provide debug printing function that collects output.
// TODO: Write results json file
// TODO: Tests for formatting, test running, etc
import gleam/io
import gleam/list
import gleam/bool
import gleam/string
import gleam/option.{None, Some}
import gleam/dynamic.{Dynamic}
import gleam/erlang/atom.{Atom}
import gleam/erlang/charlist.{Charlist}
import simplifile
import glance
import exercism_test_runner/internal.{BeamModule,
  Error, Suite, Test, TestResult}

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
  let #(passed, message) = internal.print_summary(results)
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
      io.println(internal.print_error(test, error))
      Some(error)
    }
  }
  TestResult(name: test.name, error: error, output: "")
}

external fn read_directory(String) -> Result(List(Charlist), Dynamic) =
  "file" "list_dir"

external fn atom_to_module(Atom) -> BeamModule =
  "gleam_stdlib" "identity"

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

  let src = internal.extract_function_body(src, start, end)
  let function = fn() { internal.run_test_function(module, name) }
  Ok(Test(name: name, src: src, module_path: module_path, function: function))
}

external fn halt(Int) -> a =
  "erlang" "halt"
