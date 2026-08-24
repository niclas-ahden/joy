import pf.Cmd
import pf.Stderr

## Helpers shared by the executable scripts in the repo root: build.roc,
## tests.roc, e2e.roc and watch.roc. All of them are run from the repo root.
Util :: [].{

	## Run a command with inherited stdio, exiting with the child's code when
	## it fails. A command that could not be run at all (missing binary, no
	## permission) is reported on stderr: the child never got to say anything,
	## so without this the script would die with no output at all.
	run! : Str, List(Str) => Try({}, [Exit(I32), ..])
	run! = |program, args| {
		match Cmd.new_str(program).args_str(args).exec_exit_code!() {
			Ok(0) => Ok({})
			Ok(code) => Err(Exit(code))
			Err(FailedToGetExitCode({ err, .. })) => {
				Stderr.line!("error: could not run ${program}: ${Str.inspect(err)}") ?? {}
				Err(Exit(1))
			}
		}
	}

	## run!, with one environment variable set for the child.
	run_env! : Str, List(Str), Str, Str => Try({}, [Exit(I32), ..])
	run_env! = |program, args, key, value| {
		match Cmd.new_str(program).args_str(args).env_str(key, value).exec_exit_code!() {
			Ok(0) => Ok({})
			Ok(code) => Err(Exit(code))
			Err(FailedToGetExitCode({ err, .. })) => {
				Stderr.line!("error: could not run ${program}: ${Str.inspect(err)}") ?? {}
				Err(Exit(1))
			}
		}
	}

	## Report a message on stderr and exit non-zero.
	fail! : Str => Try(ok, [Exit(I32), ..])
	fail! = |message| {
		Stderr.line!("error: ${message}") ?? {}
		Err(Exit(1))
	}

	## The app name in `examples/counter.roc`, `counter.roc` or `counter`,
	## and for directory examples in `examples/todomvc`, `examples/todomvc/`
	## or `examples/todomvc/app.roc`: the last path segment that is not
	## `app.roc`, without the `.roc`. build.roc and watch.roc both take an
	## app in any of those forms, and build.roc looks the name up in each of
	## its source directories.
	example_name : Str -> Str
	example_name = |arg| {
		trimmed = arg.drop_suffix("/").drop_suffix("/app.roc")
		base = match trimmed.split_last("/") {
			Ok(split) => split.after
			Err(_) => trimmed
		}
		base.drop_suffix(".roc")
	}
}
