import gleam/io
import gleam/list
import gleam/bool
import gleam/result
import gleam/string
import gleam/bit_string
import gleam/dynamic.{Dynamic}
import gleam/erlang/charlist.{Charlist}
import simplifile
import glance

pub fn main() {
  let assert Ok(files) = read_directory("test")
  let modules = list.map(files, read_module)
  io.debug(modules)
  Nil
}

pub type Error {
  Unequal(Dynamic, Dynamic)
  Crashed(String)
}

external fn read_directory(String) -> Result(List(Charlist), Dynamic) =
  "file" "list_dir"

fn read_module(filename: Charlist) -> Suite {
  let filename = charlist.to_string(filename)
  let name = string.drop_right(filename, 6)
  let path = "test/" <> filename
  let assert Ok(src) = simplifile.read(path)
  let assert Ok(ast) = glance.module(src)
  let tests = list.filter_map(ast.functions, get_test(src, _))
  Suite(name: name, path: path, tests: tests)
}

fn get_test(
  src: String,
  function: glance.Definition(glance.Function),
) -> Result(Test, Nil) {
  let glance.Function(name: name, location: glance.Span(start, end), ..) =
    function.definition
  use <- bool.guard(!string.ends_with(name, "_test"), Error(Nil))
  let src = extract_function_body(src, start, end)
  Ok(Test(name: name, src: src))
}

type Suite {
  Suite(name: String, path: String, tests: List(Test))
}

type Test {
  Test(name: String, src: String)
}

pub fn extract_function_body(src: String, start: Int, end: Int) -> String {
  src
  |> bit_string.from_string
  |> bit_string.slice(start, end - start)
  |> result.unwrap(<<>>)
  |> bit_string.to_string
  |> result.unwrap("")
  |> string.drop_right(1)
  |> drop_function_header
  |> string.trim
  |> string.split("\n")
  |> list.map(undent)
  |> string.join("\n")
}

fn drop_function_header(src: String) -> String {
  case string.pop_grapheme(src) {
    Ok(#("{", src)) -> src
    Ok(#(_, src)) -> drop_function_header(src)
    Error(_) -> src
  }
}

fn undent(line: String) -> String {
  case string.starts_with(line, "  ") {
    True -> string.drop_left(line, 2)
    False -> line
  }
}
