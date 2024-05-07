Unfortunately, these golden tests cannot test changes to the test_runner
until the test_runner has been published to Hex.

When PR exercism/gleam-test-runner#63 has been merged and the package
is published, then we can:
```sh
mv tests/.skip_for_now.bad_test_files tests/bad_test_files
```
