import exercism/test_runner
import exercism/should
import empty_file

pub fn main() {
  test_runner.main()
}

pub fn hello_world_test() {
  empty_file.hello_world()
  |> should.equal("Hello, from empty_file!")
}
