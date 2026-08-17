import pf.Cmd
import pf.Stderr

## Helpers shared by the executable scripts in the repo root: build.roc,
## tests.roc, e2e.roc and watch.roc. All of them are run from the repo root.
Util :: [].{

	## Run a command with inherited stdio, exiting with the child's code when it
	## fails.
	run! : Str, List(Str) => Try({}, [Exit(I32), ..])
	run! = |program, args| {
		match Cmd.new_str(program).args_str(args).exec_exit_code!() {
			Ok(0) => Ok({})
			Ok(code) => Err(Exit(code))
			Err(_) => Err(Exit(1))
		}
	}

	## run!, with one environment variable set for the child.
	run_env! : Str, List(Str), Str, Str => Try({}, [Exit(I32), ..])
	run_env! = |program, args, key, value| {
		match Cmd.new_str(program).args_str(args).env_str(key, value).exec_exit_code!() {
			Ok(0) => Ok({})
			Ok(code) => Err(Exit(code))
			Err(_) => Err(Exit(1))
		}
	}

	## Report a message on stderr and exit non-zero.
	fail! : Str => Try(ok, [Exit(I32), ..])
	fail! = |message| {
		Stderr.line!("error: ${message}") ?? {}
		Err(Exit(1))
	}

	## The app name in `examples/counter.roc`, `counter.roc` or `counter`:
	## everything after the last `/`, without the `.roc`. build.roc and
	## watch.roc both take an app in any of those forms, and build.roc looks
	## the name up in each of its source directories.
	example_name : Str -> Str
	example_name = |arg| {
		base = match arg.split_last("/") {
			Ok(split) => split.after
			Err(_) => arg
		}
		base.drop_suffix(".roc")
	}
}
