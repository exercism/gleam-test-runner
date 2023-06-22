import gleam/json
import gleam/dynamic
import gleam/option.{None, Some}
import exercism/test_runner
import exercism/should
import exercism_test_runner/internal

pub fn main() {
  test_runner.main()
}

fn one() {
  1
}

pub fn should_equal_test() {
  "one 1"
  |> should.equal("one 1")
}

pub fn let_assert_test() {
  test_runner.debug([1, 2])
  let assert 1 = one()
}

pub fn case_test() {
  case one() {
    2 -> Nil
    _ -> Nil
  }
}

pub fn todo_test() {
  // todo
  Nil
}

pub fn panic_test() {
  // panic
  Nil
}

pub fn extract_function_body_test() {
  "
pub fn main() {
  io.println(\"Hello, world!\")
}

pub fn unwrap(result, default) {
  case result {
    Ok(value) -> value
    _ -> default
  }
}

pub fn flip(f) {
  fn(a, b) {
    f(b, a)
  }
}
"
  |> internal.extract_function_body(50, 143)
  |> should.equal(
    "case result {
  Ok(value) -> value
  _ -> default
}",
  )
}

pub fn print_unequal_test() {
  internal.Unequal(dynamic.from("ab"), dynamic.from("abc"))
  |> internal.print_error("src/wibble.gleam", "wobble_test")
  |> should.equal(
    "src/wibble.gleam
   test: wobble_test
  error: left != right
   left: \"ab\"
  right: \"ab\e[1m\e[31mc\e[39m\e[22m\"",
  )
}

pub fn print_todo_test() {
  internal.Todo("ok")
  |> internal.print_error("src/wibble.gleam", "wobble_test")
  |> should.equal(
    "src/wibble.gleam
   test: wobble_test
  error: todo
   info: ok",
  )
}

pub fn print_panic_test() {
  internal.Panic("ah!")
  |> internal.print_error("src/wibble.gleam", "wobble_test")
  |> should.equal(
    "src/wibble.gleam
   test: wobble_test
  error: panic
   info: ah!",
  )
}

pub fn print_crashed_test() {
  internal.Crashed(dynamic.from(Error(Nil)))
  |> internal.print_error("src/wibble.gleam", "wobble_test")
  |> should.equal(
    "src/wibble.gleam
   test: wobble_test
  error: Program crashed
  cause: Error(Nil)",
  )
}

pub fn print_unmatched_test() {
  internal.Unmatched(dynamic.from(Ok(1)), 214)
  |> internal.print_error("src/wibble.gleam", "wobble_test")
  |> should.equal(
    "src/wibble.gleam:214
   test: wobble_test
  error: Pattern match failed
  value: Ok(1)",
  )
}

pub fn print_unmatched_case_test() {
  internal.UnmatchedCase(dynamic.from(Ok(1)))
  |> internal.print_error("src/wibble.gleam", "wobble_test")
  |> should.equal(
    "src/wibble.gleam
   test: wobble_test
  error: Pattern match failed
  value: Ok(1)",
  )
}

pub fn print_summary_passed_test() {
  let test =
    internal.Test(
      module_path: "src/wibble.gleam",
      name: "one_test",
      function: fn() { Ok(Nil) },
      src: "",
    )
  [
    internal.TestResult(test, None, ""),
    internal.TestResult(test, None, ""),
    internal.TestResult(test, None, ""),
  ]
  |> internal.print_summary
  |> should.equal(#(True, "Ran 3 tests, 0 failed"))
}

pub fn print_summary_failed_test() {
  let test =
    internal.Test(
      module_path: "src/wibble.gleam",
      name: "one_test",
      function: fn() { Ok(Nil) },
      src: "",
    )
  [
    internal.TestResult(test, Some(internal.Todo("")), ""),
    internal.TestResult(test, None, ""),
    internal.TestResult(test, None, ""),
  ]
  |> internal.print_summary
  |> should.equal(#(False, "Ran 3 tests, 1 failed"))
}

pub fn run_test_test() {
  let test =
    internal.Test(
      module_path: "src/wibble.gleam",
      name: "one_test",
      function: fn() {
        test_runner.debug([1, 2])
        test_runner.debug(Ok(Nil))
        Ok(Nil)
      },
      src: "",
    )
  test
  |> internal.run_test
  |> should.equal(internal.TestResult(test, None, "[1, 2]\nOk(Nil)\n"))
}

pub fn results_to_json_pass_test() {
  [
    internal.TestResult(
      internal.Test(
        module_path: "src/wibble.gleam",
        name: "one_test",
        function: fn() { Ok(Nil) },
        src: "src1",
      ),
      None,
      "One two three!",
    ),
    internal.TestResult(
      internal.Test(
        module_path: "src/wibble.gleam",
        name: "two_test",
        function: fn() { Ok(Nil) },
        src: "src2",
      ),
      None,
      "",
    ),
  ]
  |> internal.results_to_json
  |> should.equal(json.to_string(json.object([
    #("version", json.int(2)),
    #("status", json.string("pass")),
    #(
      "tests",
      json.preprocessed_array([
        json.object([
          #("name", json.string("one_test")),
          #("test_code", json.string("src1")),
          #("output", json.string("One two three!")),
          #("status", json.string("pass")),
        ]),
        json.object([
          #("name", json.string("two_test")),
          #("test_code", json.string("src2")),
          #("status", json.string("pass")),
        ]),
      ]),
    ),
  ])))
}

pub fn results_to_json_failed_test() {
  [
    internal.TestResult(
      internal.Test(
        module_path: "src/wibble.gleam",
        name: "one_test",
        function: fn() { Ok(Nil) },
        src: "src1",
      ),
      Some(internal.Todo("todo")),
      "One two three!",
    ),
    internal.TestResult(
      internal.Test(
        module_path: "src/wibble.gleam",
        name: "two_test",
        function: fn() { Ok(Nil) },
        src: "src2",
      ),
      None,
      "",
    ),
  ]
  |> internal.results_to_json
  |> should.equal(json.to_string(json.object([
    #("version", json.int(2)),
    #("status", json.string("fail")),
    #(
      "tests",
      json.preprocessed_array([
        json.object([
          #("name", json.string("one_test")),
          #("test_code", json.string("src1")),
          #("output", json.string("One two three!")),
          #("status", json.string("fail")),
          #(
            "message",
            json.string(internal.print_error(
              internal.Todo("todo"),
              "src/wibble.gleam",
              "one_test",
            )),
          ),
        ]),
        json.object([
          #("name", json.string("two_test")),
          #("test_code", json.string("src2")),
          #("status", json.string("pass")),
        ]),
      ]),
    ),
  ])))
}
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
//       "output": "output printed by the user", TODO: truncated to 500 characters
//     }
//   ]
// }
