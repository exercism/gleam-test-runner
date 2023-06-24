import exercism/test_runner
import exercism/should

pub fn main() {
  test_runner.main()
}

pub fn hello_world_test() {
  1
  |> should.equal(1)
}
