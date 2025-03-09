import gap
import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/erlang
import gleam/erlang/atom
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam_community/ansi

pub type Error {
  Unequal(left: Dynamic, right: Dynamic)
  Todo(message: String, module: String, line: Int)
  Panic(message: String, module: String, line: Int)
  Unmatched(value: Dynamic, module: String, line: Int)
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
  TestResult(the_test: Test, error: Option(Error), output: String)
}

pub fn extract_function_body(src: String, start: Int, end: Int) -> String {
  src
  |> bit_array.from_string
  |> bit_array.slice(start, end - start)
  |> result.unwrap(<<>>)
  |> bit_array.to_string
  |> result.unwrap("")
  |> string.drop_end(1)
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
    True -> string.drop_start(line, 2)
    False -> line
  }
}

fn print_properties(
  header: String,
  properties: List(#(String, String)),
) -> String {
  properties
  |> list.map(fn(pair) {
    let key = string.pad_start(pair.0, 7, " ") <> ": "
    ansi.cyan(key) <> pair.1
  })
  |> list.prepend(header)
  |> string.join("\n")
}

pub fn print_error(error: Error, path: String, test_name: String) -> String {
  case error {
    Unequal(left, right) -> {
      let #(left_colored, right_colored) = case
        decode.run(left, decode.bool),
        decode.run(right, decode.bool)
      {
        Ok(left_bool), Ok(right_bool) -> #(
          left_bool
            |> string.inspect()
            |> ansi.green()
            |> ansi.bold(),
          right_bool
            |> string.inspect()
            |> ansi.red()
            |> ansi.bold(),
        )
        _, _ -> {
          let diff =
            gap.to_styled(gap.compare_strings(
              string.inspect(left),
              string.inspect(right),
            ))
          #(diff.first, diff.second)
        }
      }

      path
      |> print_properties([
        #("test", test_name),
        #("error", "left != right"),
        #("left", left_colored),
        #("right", right_colored),
      ])
    }
    Todo(message, module, line) -> {
      print_properties(path, [
        #("test", test_name),
        #("error", "todo"),
        #("site", module <> ":" <> int.to_string(line)),
        #("info", message),
      ])
    }
    Panic(message, module, line) -> {
      print_properties(path, [
        #("test", test_name),
        #("error", "panic"),
        #("site", module <> ":" <> int.to_string(line)),
        #("info", message),
      ])
    }
    Unmatched(value, module, line) -> {
      print_properties(path, [
        #("test", test_name),
        #("error", "Pattern match failed"),
        #("site", module <> ":" <> int.to_string(line)),
        #("value", string.inspect(value)),
      ])
    }
    UnmatchedCase(value) -> {
      print_properties(path, [
        #("test", test_name),
        #("error", "Pattern match failed"),
        #("value", string.inspect(value)),
      ])
    }
    Crashed(error) -> {
      print_properties(path, [
        #("test", test_name),
        #("error", "Program crashed"),
        #("cause", string.inspect(error)),
      ])
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

  let colour = case failed {
    "0" -> ansi.green
    _ -> ansi.red
  }
  let message = colour("Ran " <> total <> " tests, " <> failed <> " failed")
  #(failed == "0", message)
}

pub fn run_test_function(function: fn() -> a) -> Result(Nil, Error) {
  function
  |> erlang.rescue
  |> result.map_error(convert_error)
  |> result.replace(Nil)
}

fn convert_error(error: erlang.Crash) -> Error {
  case error {
    erlang.Exited(error) -> Crashed(error)
    erlang.Thrown(error) -> Crashed(error)
    erlang.Errored(error) -> {
      let decoders =
        decode.one_of(decode_unequal_error(), [
          decode_pattern_match_failed_error(),
          decode_case_clause_error(),
          decode_todo_error(),
          decode_panic_error(),
        ])

      error
      |> decode.run(decoders)
      |> result.unwrap(Crashed(error))
    }
  }
}

fn decode_pattern_match_failed_error() -> Decoder(Error) {
  use _ <- decode.field(
    atom.create_from_string("gleam_error"),
    decode_tag(atom.create_from_string("let_assert")),
  )
  use value <- decode.field(atom.create_from_string("value"), decode.dynamic)
  use module <- decode.field(atom.create_from_string("module"), decode.string)
  use line <- decode.field(atom.create_from_string("line"), decode.int)
  decode.success(Unmatched(value, module, line))
}

fn decode_todo_error() -> Decoder(Error) {
  use _ <- decode.field(
    atom.create_from_string("gleam_error"),
    decode_tag(atom.create_from_string("todo")),
  )
  use message <- decode.field(atom.create_from_string("message"), decode.string)
  use module <- decode.field(atom.create_from_string("module"), decode.string)
  use line <- decode.field(atom.create_from_string("line"), decode.int)
  decode.success(Todo(message, module, line))
}

fn decode_panic_error() -> Decoder(Error) {
  use _ <- decode.field(
    atom.create_from_string("gleam_error"),
    decode_tag(atom.create_from_string("panic")),
  )
  use message <- decode.field(atom.create_from_string("message"), decode.string)
  use module <- decode.field(atom.create_from_string("module"), decode.string)
  use line <- decode.field(atom.create_from_string("line"), decode.int)
  decode.success(Panic(message, module, line))
}

fn decode_case_clause_error() -> Decoder(Error) {
  use _ <- decode.field(0, decode_tag(atom.create_from_string("case_clause")))
  use value <- decode.field(1, decode.dynamic)
  decode.success(UnmatchedCase(value))
}

fn decode_unequal_error() -> Decoder(Error) {
  let tag = atom.create_from_string("unequal")
  use _ <- decode.field(0, decode_tag(tag))
  use a <- decode.field(1, decode.dynamic)
  use b <- decode.field(2, decode.dynamic)
  decode.success(Unequal(a, b))
}

fn decode_tag(tag: anything) -> Decoder(Nil) {
  decode.new_primitive_decoder("Tag", fn(data) {
    case dynamic.from(tag) == data {
      True -> Ok(Nil)
      False -> Error(Nil)
    }
  })
}

pub type ProcessDictionaryKey {
  ExecismTestRunnerUserOutput
}

@external(erlang, "erlang", "put")
fn process_dictionary_set(a: ProcessDictionaryKey, b: String) -> Dynamic

@external(erlang, "erlang", "get")
fn process_dictionary_get(a: ProcessDictionaryKey) -> Dynamic

/// Append a string to the output store in the process dictionary.
/// In future it may be preferable to use a global actor or similar so we can
/// merge in any writing to stdout. Writing to stderr is not possible to
/// capture.
pub fn append_output(value: String) -> Nil {
  ExecismTestRunnerUserOutput
  |> process_dictionary_get
  |> decode.run(decode.string)
  |> result.unwrap("")
  |> string.append(value)
  |> string.append("\n")
  |> process_dictionary_set(ExecismTestRunnerUserOutput, _)
  Nil
}

pub fn clear_output() -> Nil {
  process_dictionary_set(ExecismTestRunnerUserOutput, "")
  Nil
}

pub fn get_output() -> String {
  ExecismTestRunnerUserOutput
  |> process_dictionary_get
  |> decode.run(decode.string)
  |> result.unwrap("")
}

pub fn run_test(the_test: Test) -> TestResult {
  clear_output()
  let error = case the_test.function() {
    Ok(_) -> None
    Error(error) -> Some(error)
  }
  TestResult(the_test: the_test, error: error, output: get_output())
}

pub fn results_to_json(results: List(TestResult)) -> String {
  let failed = list.any(results, fn(the_test) { the_test.error != None })
  let status = case failed {
    True -> "fail"
    False -> "pass"
  }
  json.object([
    #("version", json.int(2)),
    #("status", json.string(status)),
    #("tests", json.array(results, test_result_json)),
  ])
  |> json.to_string
}

fn test_result_json(result: TestResult) -> Json {
  let fields = case result.error {
    Some(error) -> {
      let error =
        print_error(error, result.the_test.module_path, result.the_test.name)
      [#("status", json.string("fail")), #("message", json.string(error))]
    }
    None -> [#("status", json.string("pass"))]
  }
  let fields = case truncate(result.output) {
    "" -> fields
    output -> [#("output", json.string(output)), ..fields]
  }
  let fields = [
    #("name", json.string(result.the_test.name)),
    #("test_code", json.string(result.the_test.src)),
    ..fields
  ]
  json.object(fields)
}

fn truncate(output: String) -> String {
  case string.length(output) > 500 {
    True ->
      output
      |> string.slice(0, 448)
      |> string.append("...\n\n")
      |> string.append("Output was truncated. Please limit to 500 chars")
    False -> output
  }
}
