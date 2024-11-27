#!/usr/bin/env bash

# THIS SCRIPT IS USED TO (RE)GENERATE THE GLUE CODE FOR THE PLATFORM
#
# I NORMALLY COPY JUST THE PARTS I NEED AND THEN MANUALLY CHANGE THINGS HOW I LIKE

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

roc glue ../roc/crates/glue/src/RustGlue.roc asdf platform/glue.roc
