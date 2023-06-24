#!/usr/bin/env sh

# Synopsis:
# Test the test runner by running it against a predefined set of solutions 
# with an expected output.

# Output:
# Outputs the diff of the expected test results against the actual test results
# generated by the test runner.

# Example:
# ./bin/run-tests.sh

set -eu

exit_code=0

# Iterate over all test directories
for test_dir in tests/*; do
  test_dir_name=$(basename "${test_dir}")
  test_dir_path=$(realpath "${test_dir}")
  results_file_path="${test_dir_path}/results.json"
  expected_results_file_path="${test_dir_path}/expected_results.json"

  echo "${test_dir_name}: testing..."
  rm -f "${results_file_path}"
  bin/run.sh "${test_dir_name}" "${test_dir_path}" "${test_dir_path}" > /dev/null

  if cat "${results_file_path}" | jq . | diff - "${expected_results_file_path}" --color=always
  then
    echo "${test_dir_name}: pass"
  else
    echo
    echo "${test_dir_name}: fail."
    echo "${test_dir_name}: ${results_file_path} does not match ${expected_results_file_path}"
    exit_code=1
  fi
  echo
done

if [ "${exit_code}" -eq 0 ]
then
  echo "All tests passed!"
else
  echo "Some tests failed!"
fi

exit ${exit_code}
