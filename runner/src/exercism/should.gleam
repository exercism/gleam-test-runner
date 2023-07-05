import exercism_test_runner/internal.{Error, Unequal}
import gleam/dynamic

@external(erlang, "erlang", "error")
fn raise(a: Error) -> a

pub fn equal(a, b) {
  case a == b {
    True -> a
    False -> raise(Unequal(dynamic.from(a), dynamic.from(b)))
  }
}
