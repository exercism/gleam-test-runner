import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn one_test() {
  "one"
  |> should.equal("oops")
}

pub fn two_test() {
  "two"
  |> should.equal("oops")
}
