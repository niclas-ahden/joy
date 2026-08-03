#!/usr/bin/env roc
# Run:
#
#   ./tests.roc
#
# To build everything (see build.roc) and run the node harness checks. Run from
# the repo root.
#
# Environment variables pass straight through to build.roc, so
# `SMALL_BUFFERS=1 ./tests.roc` runs the whole suite with tiny initial outbound
# buffers, exercising the buffer growth path on every render.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.23.0/7NpDhuqoqGFedmVLvmm1zjq37GCmaFGzwr5sz4ch9wTK.tar.zst",
}

import pf.Path
import pf.Stdout
import Util exposing [run!]

main! = |_args| {
	# Roc-level unit tests: top-level `expect`s in the platform modules (pure
	# code: the Cmd/Sub/Attribute/Html `map` plumbing, WebCrypto.to_hex, ...).
	# `roc test` on main.roc runs the expects of every module it imports.
	Stdout.line!("== roc test platform/main.roc")?
	run!("roc", ["test", "platform/main.roc"])?

	run!("./build.roc", [])?

	# node:test runs each harness in its own child process (concurrently) and
	# keeps going past a failing file, so one broken harness can't hide the
	# rest.
	harnesses = Path.utf8("tests").list!()?
		.keep_if(|entry| is_harness(Path.display(Path.filename(entry).ok_or(entry))))
		.map(Path.display)
	run!("node", ["--test"].concat(harnesses))?

	Ok({})
}

is_harness = |name| name.starts_with("check_") and name.ends_with(".mjs")
