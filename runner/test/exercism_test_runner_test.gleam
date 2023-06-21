import exercism_test_runner
import exercism_test_runner/should

pub fn main() {
  exercism_test_runner.main()
}

pub fn hello_world_test() {
  1
  |> should.equal(1)
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
  |> exercism_test_runner.extract_function_body(50, 143)
  |> should.equal(
    "case result {
  Ok(value) -> value
  _ -> default
}",
  )
}
