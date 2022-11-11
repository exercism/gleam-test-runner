import gleeunit
import gleeunit/should
import empty_file

pub fn main() {
  gleeunit.main()
}

pub fn hello_world_test() {
  empty_file.hello_world()
  |> should.equal("Hello, from empty_file!")
}
