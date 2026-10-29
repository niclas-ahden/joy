import pf.Cmd
import pf.OsStr
import pf.Stderr

## Helpers shared by the executable scripts in the repo root: build.roc,
## tests.roc, e2e.roc and watch.roc. All of them are run from the repo root.
Util :: [].{

	## Run a command with inherited stdio, exiting with the child's code when
	## it fails. A command that could not be run at all (missing binary, no
	## permission) is reported on stderr: the child never got to say anything,
	## so without this the script would die with no output at all.
	run! : Str, List(Str) => Try({}, [Exit(I32)])
	run! = |program, args| {
		match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).inherit_stdio().run!() {
			Ok(output) => Util.exit_of(output.status)
			Err(err) => {
				Stderr.line!("error: could not run ${program}: ${Str.inspect(err)}") ?? {}
				Err(Exit(1))
			}
		}
	}

	## run!, with one environment variable set for the child.
	run_env! : Str, List(Str), Str, Str => Try({}, [Exit(I32)])
	run_env! = |program, args, key, value| {
		match Cmd.new(OsStr.from_str(program)).args(args.map(OsStr.from_str)).env(OsStr.from_str(key), OsStr.from_str(value)).inherit_stdio().run!() {
			Ok(output) => Util.exit_of(output.status)
			Err(err) => {
				Stderr.line!("error: could not run ${program}: ${Str.inspect(err)}") ?? {}
				Err(Exit(1))
			}
		}
	}

	## Ok for a child that exited with code 0, its exit code otherwise. A
	## child killed by a signal exits 1.
	exit_of : Cmd.ExitStatus -> Try({}, [Exit(I32)])
	exit_of = |status|
		match status {
			Exited(0) => Ok({})
			Exited(code) => Err(Exit(code))
			Signaled(_) => Err(Exit(1))
		}

	## Report a message on stderr and exit non-zero.
	fail! : Str => Try(ok, [Exit(I32)])
	fail! = |message| {
		Stderr.line!("error: ${message}") ?? {}
		Err(Exit(1))
	}

	## The app name in `examples/counter.roc`, `counter.roc` or `counter`,
	## and for directory examples in `examples/spa-todomvc`, `examples/spa-todomvc/`
	## or `examples/spa-todomvc/app.roc`: the last path segment that is not
	## `app.roc`, without the `.roc`. build.roc and watch.roc both take an
	## app in any of those forms, and build.roc looks the name up in each of
	## its source directories.
	example_name : Str -> Str
	example_name = |arg| {
		# A Windows path listing separates with backslashes. The name is the
		# same either way.
		trimmed = arg.replace_each("\\", "/").drop_suffix("/").drop_suffix("/app.roc")
		base = match trimmed.split_last("/") {
			Ok(split) => split.after
			Err(_) => trimmed
		}
		base.drop_suffix(".roc")
	}
}
