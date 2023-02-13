import gleeunit
import gleeunit/should
import gleam/bitwise

pub fn main() {
  gleeunit.main()
}

pub fn bitwise_test() {
  bitwise.shift_left(1, 1)
  |> should.equal(2)
}
