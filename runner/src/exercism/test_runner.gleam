// TODO: Get and show stacktrace
import argv
import exercism_test_runner/internal.{
  type Suite, type Test, type TestResult, Suite, Test,
}
import glance
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/charlist.{type Charlist}
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam_community/ansi
import simplifile

pub fn main() {
  let assert Ok(files) = read_directory("test")
  let files =
    list.map(files, charlist.to_string)
    |> list.filter(fn(file) {
      string.ends_with(file, "test.gleam") && !string.starts_with(file, ".")
    })
  let suites = list.map(files, read_module)
  let results = list.flat_map(suites, run_suite)
  let #(passed, message) = internal.print_summary(results)
  io.println("\n" <> message)

  let assert Ok(_) = case argv.load().arguments {
    ["--json-output-path=" <> path] | ["--json-output-path", path] -> {
      let json = internal.results_to_json(results)
      simplifile.write(path, json)
    }
    _ -> Ok(Nil)
  }

  halt(case passed {
    True -> 0
    False -> 1
  })
}

pub fn debug(value: anything) -> anything {
  internal.append_output(string.inspect(value))
  value
}

fn run_suite(suite: Suite) -> List(TestResult) {
  list.map(suite.tests, run_test)
}

fn run_test(the_test: Test) -> TestResult {
  let result = internal.run_test(the_test)
  case result.error {
    None -> io.print(ansi.green("."))
    Some(error) -> {
      io.println(ansi.red("F"))
      io.println(internal.print_error(
        error,
        the_test.module_path,
        the_test.name,
      ))
    }
  }
  result
}

@external(erlang, "file", "list_dir")
fn read_directory(a: String) -> Result(List(Charlist), Dynamic)

@external(erlang, "gleam_stdlib", "identity")
fn atom_to_module(a: Atom) -> BeamModule

fn read_module(filename: String) -> Suite {
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
  let function = fn() {
    internal.run_test_function(fn() {
      apply(module, atom.create_from_string(name), [])
    })
  }
  Ok(Test(name: name, src: src, module_path: module_path, function: function))
}

pub type BeamModule

/// This function is unsafe. It does not verify that the atom is a BEAM module
/// currently loaded by the VM, or that the function exists. Don't mess up!
@external(erlang, "erlang", "apply")
fn apply(a: BeamModule, b: Atom, c: List(Dynamic)) -> Dynamic

@external(erlang, "erlang", "halt")
fn halt(a: Int) -> a
