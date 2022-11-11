import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn one_test() {
  "one"
  |> should.equal("one")
}

pub fn two_test() {
  "two"
  |> should.equal("two")
}

pub fn three_test() {
  "three"
  |> should.equal("oops")
}
