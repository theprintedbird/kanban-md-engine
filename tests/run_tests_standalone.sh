#!/usr/bin/env bash
# Run the standalone Lua test suite.
#
#   tests/run_tests_standalone.sh              # normal output
#   TAP=1 tests/run_tests_standalone.sh        # TAP output on stdout
#   TAP_FILE=busted-tap.txt tests/run_tests_standalone.sh
#                                              # TAP output, also saved to a file
#
# Any extra arguments are passed straight through to busted, so
# `tests/run_tests_standalone.sh --shuffle` works as expected.

set -eu

if [ -n "${TAP_FILE:-}" ]; then
  TAP=1
fi

if [ "${TAP:-}" = "1" ]; then
  set -o pipefail
  if [ -n "${TAP_FILE:-}" ]; then
    busted --output=TAP "$@" | tee "$TAP_FILE"
  else
    busted --output=TAP "$@"
  fi
else
  busted "$@"
fi
