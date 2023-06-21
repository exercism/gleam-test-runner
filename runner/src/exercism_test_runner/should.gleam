import exercism_test_runner.{Error, Unequal}
import gleam/dynamic

external fn raise(Error) -> Nil =
  "erlang" "error"

pub fn equal(a, b) {
  case a == b {
    True -> Nil
    False -> raise(Unequal(dynamic.from(a), dynamic.from(b)))
  }
}
