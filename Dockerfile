FROM ghcr.io/gleam-lang/gleam:v1.10.0-erlang-alpine

# Install packages required to run the tests
RUN apk add --no-cache jq coreutils

WORKDIR /opt/test-runner
COPY . .

# Download the used Gleam packages eagerly as the test runner will not have
# network access to do so. They are also pre-compiled for performance when
# compiling test projects. The compiled modules are also copied into one
# directory, so the Erlang VM searches one directory for each module instead
# of one per package.
RUN cd packages \
  && gleam deps download \
  && gleam build \
  && mkdir ../ebin \
  && cp build/dev/erlang/*/ebin/* ../ebin/

ENTRYPOINT ["/opt/test-runner/bin/run.sh"]
