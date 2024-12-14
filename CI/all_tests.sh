#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -exo pipefail

# sanity check
roc version

./watch.sh examples/hello.roc 2>&1 | tee watch_output.log &
WATCH_PID=$!

while true; do
    # Check if watch process is still running
    if ! kill -0 $WATCH_PID 2>/dev/null; then
        echo "Failure: watch.sh process terminated unexpectedly!"
        exit 1
    fi

    # Check for success message in log
    if grep -q "\[Command was successful\]" watch_output.log; then
        break
    fi

    sleep 10
done

curl -sS localhost:3000 | grep demo