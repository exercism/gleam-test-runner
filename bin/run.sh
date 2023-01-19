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
solution_dir=$(realpath "${2%/}")
output_dir=$(realpath "${3%/}")
results_file="${output_dir}/results.json"

# The container environment does not have network access in order to download
# dependencies so we copy them from a precompiled Gleam project.
# The config for this project is also copied to ensure that the build tool does
# not attempt to download some other version of the dependencies or any
# additional ones.
#
echo "Copying config and dependencies..."
mkdir -p "$solution_dir"
rm -fr "$solution_dir"/build
cp -r "$root_dir"/packages/build "$solution_dir"/build
cp -r "$root_dir"/packages/gleam.toml "$solution_dir"/gleam.toml
cp -r "$root_dir"/packages/manifest.toml "$solution_dir"/manifest.toml

sanitise_gleam_output() {
  grep -vE \
    -e "^Downloading packages" \
    -e "^ Downloaded [0-9]+ packages in [0-9]\.[0-9]+s" \
    -e "^  Compiling [a-z0-9_]+$" \
    -e "^   Compiled in [0-9]+\.[0-9]+s" \
    -e "^    Running [a-z0-9_]+\.main" \
    -e "^Finished in [0-9]+\.[0-9]+"
}

# Create the output directory if it doesn't exist
mkdir -p "${output_dir}"

# Compile the project
echo "${slug}: compiling..."

cd "${solution_dir}" || exit 1

if ! output=$(gleam build 2>&1)
then
  output=$(echo "${output}" | sanitise_gleam_output)
  jq -n --arg output "${output}" '{version: 1, status: "error", message: $output}' > "${results_file}"
  echo "Compilation contained error, see ${output_dir}/results.json"
  exit 0
fi

echo "${slug}: testing..."

# Run the tests for the provided implementation file and redirect stdout and
# stderr to capture it
# Write the results.json file based on the exit code of the command that was 
# just executed that tested the implementation file
if output=$(gleam test 2>&1)
then
  jq -n '{version: 1, status: "pass"}' > "${results_file}"
else
  output=$(echo "${output}" | sanitise_gleam_output)
  jq -n --arg output "${output}" '{version: 1, status: "fail", message: $output}' > "${results_file}"
fi

echo "${slug}: done"
