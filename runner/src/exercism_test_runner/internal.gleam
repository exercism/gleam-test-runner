import gap
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/option.{None, Option}
import gleam/bit_string
import gleam/dynamic.{Dynamic}
import gleam/erlang
import gleam/erlang/atom.{Atom}

pub type Error {
  Unequal(left: Dynamic, right: Dynamic)
  Todo(message: String)
  Panic(message: String)
  Unmatched(value: Dynamic, line: Int)
  UnmatchedCase(value: Dynamic)
  Crashed(error: Dynamic)
}

pub type Suite {
  Suite(name: String, path: String, tests: List(Test))
}

pub type Test {
  Test(
    name: String,
    module_path: String,
    function: fn() -> Result(Nil, Error),
    src: String,
  )
}

pub type TestResult {
  TestResult(name: String, error: Option(Error), output: String)
}

pub type BeamModule

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

pub fn print_error(test: Test, error: Error) -> String {
  case error {
    Unequal(left, right) -> {
      let diff =
        gap.compare_strings(string.inspect(left), string.inspect(right))
        |> gap.to_styled
      string.join(
        [
          test.module_path,
          "   test: " <> test.name,
          "  error: left != right",
          "   left: " <> diff.first,
          "  right: " <> diff.second,
        ],
        "\n",
      )
    }
    Todo(message) -> {
      string.join(
        [test.module_path, "   test: " <> test.name, "  error: " <> message],
        "\n",
      )
    }
    Panic(message) -> {
      string.join(
        [test.module_path, "   test: " <> test.name, "  error: " <> message],
        "\n",
      )
    }
    Unmatched(value, line) -> {
      string.join(
        [
          test.module_path <> ":" <> int.to_string(line),
          "   test: " <> test.name,
          "  error: Pattern match failed",
          "  value: " <> string.inspect(value),
        ],
        "\n",
      )
    }
    UnmatchedCase(value) -> {
      string.join(
        [
          test.module_path,
          "   test: " <> test.name,
          "  error: Pattern match failed",
          "  value: " <> string.inspect(value),
        ],
        "\n",
      )
    }
    Crashed(error) -> {
      string.join(
        [
          test.module_path,
          "   test: " <> test.name,
          "  error: Program crashed",
          "         " <> string.inspect(error),
        ],
        "\n",
      )
    }
  }
}

pub fn print_summary(results: List(TestResult)) -> #(Bool, String) {
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

/// This function is unsafe. It does not verify that the atom is a BEAM module
/// currently loaded by the VM, or that the function exists. Don't mess up!
external fn apply(BeamModule, Atom, List(Dynamic)) -> Dynamic =
  "erlang" "apply"

pub fn run_test_function(module: BeamModule, name: String) -> Result(Nil, Error) {
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
