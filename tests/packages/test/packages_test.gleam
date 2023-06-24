import exercism/test_runner
import exercism/should
import gleam/bitwise

pub fn main() {
  test_runner.main()
}

pub fn bitwise_test() {
  bitwise.shift_left(1, 1)
  |> should.equal(2)
}
