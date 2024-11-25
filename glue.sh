#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc glue ../roc/crates/glue/src/RustGlue.roc asdf platform/glue.roc
