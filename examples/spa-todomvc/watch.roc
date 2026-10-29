#!/usr/bin/env roc
# Run:
#
#   ./watch.roc
#
# Serves the app at http://localhost:8000. Edit app.roc (or anything else)
# and it rebuilds automatically. Refresh the page to see your changes (there
# is no browser hot-reloading yet).
#
# Uses `roc build --watch` which writes no wasm at all in most error cases
# (e.g. type errors). If you refresh your browser and your app isn't showing up,
# then check your terminal for errors (you'll also see a crash in the browser
# console).
#
# Set the environment variable `JOY_WATCH_PORT` to change the port (default 8000).
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
}

import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Sleep
import pf.Stderr
import pf.Stdout

main! = |_args| {
	port = Env.var_str!("JOY_WATCH_PORT") ?? "8000"

	# ./build.roc once up front so that Joy's assets are in place when the server starts
	# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash
	# this compile. Drop `--no-cache` when fixed.
	build = Cmd.new(OsStr.from_str("roc")).args([OsStr.from_str("--no-cache"), OsStr.from_str("./build.roc")]).inherit_stdio().run!()

	build_code = match build {
		Ok(output) => exit_code(output.status)
		Err(failure) => log_and_exit!("./build.roc", failure)?
	}

	if build_code != 0 {
		Stderr.line!("Warning: The first build failed, watching for changes anyway")?
	} else {
		{}
	}

	spawned =
		Cmd.new(OsStr.from_str("caddy"))
			.args(["run", "--config", "Caddyfile", "--adapter", "caddyfile"].map(OsStr.from_str))
			.env(OsStr.from_str("JOY_WATCH_PORT"), OsStr.from_str(port))
			.stderr(Capture)
			.spawn!()

	caddy = match spawned {
		Ok(child) => child
		Err(err) => log_and_exit!("caddy", err)?
	}

	# spawn! only reports that the process started, so give caddy a moment to parse its
	# config, then poll! to verify it's running
	Sleep.millis!(200)?

	match poll!(caddy) {
		Ok(Running) => {}
		Ok(Finished(exited)) => {
			code = match exited.status {
				Exited(c) => c.to_str()
				Signaled(signal) => "signal ${signal.to_str()}"
			}
			Stderr.line!("Error: caddy exited immediately (code ${code}). Is ./Caddyfile OK?")?
			Stderr.line!(Str.from_utf8_lossy(exited.stderr_bytes))?
			Err(Exit(1))?
		}
		Err(_) => Err(Exit(2))?
	}

	Stdout.line!("=> Serving the app at http://localhost:${port}")?

	watch =
		Cmd.new(OsStr.from_str("roc"))
			.args(["build", "--watch", "--target=wasm32", "--output=www/app.wasm", "app.roc"].map(OsStr.from_str))
			.inherit_stdio()
			.run!()

	# `roc build --watch` above blocks, so we're killing caddy only when roc is dead
	caddy.close!() ?? {}

	match watch {
		Ok(output) =>
			match exit_code(output.status) {
				0 => Ok({})
				code => Err(Exit(code))
			}

		Err(failure) => log_and_exit!("roc", failure)
	}
}

# WORKAROUND: roc-lang/roc#12692. A dev build frees a Child whose method a
# `match` with an early return called, which kills the child. Call
# `child.poll!()` directly when fixed.
poll! = |child| child.poll!()

# A child's exit code, 1 for one killed by a signal.
exit_code : Cmd.ExitStatus -> I32
exit_code = |status|
	match status {
		Exited(code) => code
		Signaled(_) => 1
	}

log_and_exit! = |program, err| {
	reason = match err {
		CmdErr(StartFailed(NotFound, _)) => "Not found (is it installed and available on PATH?)"
		other => Str.inspect(other)
	}

	Stderr.line!("Error: Could not run `${program}`: ${reason}")?
	Err(Exit(1))
}
