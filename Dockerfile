FROM ghcr.io/gleam-lang/gleam:v0.24.0-erlang-alpine

# install packages required to run the tests
RUN apk add --no-cache jq coreutils

WORKDIR /opt/test-runner
COPY . .
ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
