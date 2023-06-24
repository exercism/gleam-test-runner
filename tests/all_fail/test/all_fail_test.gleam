import exercism/test_runner
import exercism/should

pub fn main() {
  test_runner.main()
}

pub fn one_test() {
  "one"
  |> should.equal("oops")
}

pub fn two_test() {
  "two"
  |> should.equal("oops")
}
