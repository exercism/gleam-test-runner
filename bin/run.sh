#!/usr/bin/env sh

# Synopsis:
# Run the test runner on a solution.

# Arguments:
# $1: exercise slug
# $2: path to solution folder
# $3: path to output directory

# Output:
# Writes the test results to a results.json file in the passed-in output directory.
# The test results are formatted according to the specifications at https://github.com/exercism/docs/blob/main/building/tooling/test-runners/interface.md

# Example:
# ./bin/run.sh two-fer path/to/solution/folder/ path/to/output/directory/

# If any required arguments is missing, print the usage and exit
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
  echo "usage: ./bin/run.sh exercise-slug path/to/solution/folder/ path/to/output/directory/"
  exit 1
fi

set -eu

root_dir=$(dirname "$(dirname "$(realpath "$0")")")
slug="$1"
underscore_slug=$(echo "$slug" | tr - _)
solution_dir=$(realpath "${2%/}")
output_dir=$(realpath "${3%/}")
results_file="${output_dir}/results.json"
manifest_file="${solution_dir}/manifest.toml"
manifest_file_bak="${manifest_file}.bak"
gleam_file="${solution_dir}/gleam.toml"
gleam_file_bak="${gleam_file}.bak"
if [[ ${EXERCISM_GLEAM_LOCAL:-} == "true" ]]; then
  local=true
else
  local=false
fi

remove_unwanted_compiler_lines() {
  grep -vE \
    -e "^Downloading packages" \
    -e "^ Downloaded [0-9]+ packages in [0-9]\.[0-9]+s" \
    -e "^  Compiling [a-z0-9_]+$" \
    -e "^   Compiled in [0-9]+\.[0-9]+s" \
    -e "^    Running [a-z0-9_]+\.main" \
    -e "^Finished in [0-9]+\.[0-9]+"
}

remove_erlang_lines() {
  grep -vE \
    -e "^$" \
    -e "^% " \
    -e "^build/.*\.erl:[0-9]+:[0-9]+: "
}

remove_filepath_prefixes() {
  sed "s|${solution_dir}/||"
}

sanitise_gleam_output() {
  remove_unwanted_compiler_lines | remove_filepath_prefixes | remove_erlang_lines
}

# The container environment does not have network access in order to download
# dependencies so we copy them from a precompiled Gleam project.
# The config for this project is also copied to ensure that the build tool does
# not attempt to download some other version of the dependencies or any
# additional ones.
#
echo "Copying config and dependencies..."

cp "${manifest_file}" "${manifest_file_bak}"
cp "${gleam_file}" "${gleam_file_bak}"
rm -fr "$solution_dir"/build
cp -r "$root_dir"/packages/build "$solution_dir"/build
if [[ $local == true ]]; then
  sed "s|{ name = \"exercism_test_runner\", version = \"\([0-9.]*\)\", build_tools = \[\"gleam\"\], requirements = \[\(.*\)\].*}|{ name = \"exercism_test_runner\", version = \"\1\", build_tools = [\"gleam\"], requirements = [\2], source = \"local\", path = \"${root_dir}/runner\" }|;
    s|exercism_test_runner = .*|exercism_test_runner = { path = \"${root_dir}/runner\" }|" \
    "$root_dir"/packages/manifest.toml > "${manifest_file}"
  sed "s/name = \".*\"/name = \"$underscore_slug\"/;
    s|exercism_test_runner = .*|exercism_test_runner = { path = \"${root_dir}/runner\" }|" \
    "$root_dir"/packages/gleam.toml  > "${gleam_file}"
else
  cp "$root_dir"/packages/manifest.toml "${manifest_file}"
  sed "s/name = \".*\"/name = \"$underscore_slug\"/" "$root_dir"/packages/gleam.toml > "${gleam_file}"
fi

trap "mv ${manifest_file_bak} ${manifest_file} && mv ${gleam_file_bak} ${gleam_file}" EXIT

# Create the output directory if it doesn't exist
mkdir -p "${output_dir}"

# Compile the project
echo "${slug}: compiling..."

cd "${solution_dir}" || exit 1

# Remove the precompiled Erlang files to ensure that they do not get copied and
# compiled into .BEAM files by the Gleam build tool.
rm build/packages/*/src/*.erl

if ! output=$(gleam build 2>&1); then
  output=$(echo "${output}" | sanitise_gleam_output)
  jq -n --arg output "${output}" '{version: 2, status: "error", message: $output}' > "${results_file}"
  echo "Compilation contained error, see ${output_dir}/results.json"
  exit 0
fi

echo "${slug}: testing..."

# Run the tests for the provided implementation file.
gleam test -- --json-output-path="$results_file" 2>&1 || true

echo "${slug}: done"
