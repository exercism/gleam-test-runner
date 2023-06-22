import exercism_test_runner/internal.{Error, Unequal}
import gleam/dynamic

external fn raise(Error) -> a =
  "erlang" "error"

pub fn equal(a, b) {
  case a == b {
    True -> a
    False -> raise(Unequal(dynamic.from(a), dynamic.from(b)))
  }
}
