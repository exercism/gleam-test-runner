#!/usr/bin/env sh

# Synopsis:
# Setup the test runner locally by pre-downloading and compiling dependency
# packages.

# Example:
# ./bin/setup-locally.sh

set -eu

root_dir=$(dirname "$(dirname "$(realpath "$0")")")
cd "$root_dir"/packages
gleam build
