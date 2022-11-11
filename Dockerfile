FROM ghcr.io/gleam-lang/gleam:v0.24.0-erlang-alpine

RUN \
  # install packages required to run the tests
  apk add --no-cache jq coreutils \
  # Download the used Gleam packages
  echo get the packages here


WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
