import exercism/should
import exercism/test_runner
import gleam/int

pub fn main() {
  test_runner.main()
}

pub fn bitwise_test() {
  int.bitwise_shift_left(1, 1)
  |> should.equal(2)
}
