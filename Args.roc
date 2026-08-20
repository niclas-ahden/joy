import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import Util exposing [fail!]

## Argument parsing shared by the executable scripts in the repo root, built
## on weaver. Every script takes `--opt=<level>`, mirroring roc's own flag,
## and each level builds into its own build/<opt>/ tree.
##
## The scripts run through a plain `#!/usr/bin/env roc` shebang, so roc's `--`
## separator has to come before these flags: `./tests.roc -- --opt=dev`.
## Without it roc claims --opt and --help for itself. Plain arguments, like an
## app name, need no separator.
Args :: [].{

	## The `--opt` option itself, one definition for every script's parser.
	## Required, weaver reports it when missing.
	opt_option = Opt.str({
		short: "",
		long: "opt",
		help: "Optimization level: speed, dev, interpreter or size.",
		default: NoDefault,
	})

	## The same option with a level to fall back on, for scripts where one
	## level is the obvious choice. watch.roc serves the dev loop and wants
	## speed, so `./watch.roc examples/counter.roc` needs no flag at all.
	opt_option_with_default = |level|
		Opt.str({
			short: "",
			long: "opt",
			help: "Optimization level: speed, dev, interpreter or size (default: ${level}).",
			default: Value(level),
		})

	## Run a script's parser over its args. Help and version requests print
	## and exit zero, usage errors print and exit non-zero, so callers only
	## see a parsed config. `example` is the script's own arguments, e.g.
	## "--opt=speed", shown by separator_hint! when they went missing.
	parse! = |parser, args, example| {
		match Cli.parse_or_display_message(parser, args.drop_first(1), |arg| Utf8(OsStr.display(arg))) {
			Err(Help(message)) => {
				Stdout.line!(message)?
				Err(Exit(0))
			}

			Err(Version(message)) => {
				Stdout.line!(message)?
				Err(Exit(0))
			}

			Err(InvalidUsage(message)) => {
				Stdout.line!(message)?
				separator_hint!(args, example)?
				Err(Exit(1))
			}

			Ok(config) => Ok(config)
		}
	}

	## A forgotten `--` leaves the script with no arguments at all: roc took
	## them. Weaver can only report the option it did not get, so name the
	## likely cause when the script was handed nothing but its own path.
	separator_hint! = |args, example|
		if args.len() > 1 {
			Ok({})
		} else {
			match args.first() {
				Err(_) => Ok({})
				Ok(script) =>
					Stdout.line!(
						Str.join_with(
							[
								"",
								"This script received no arguments. If you passed some, roc claimed",
								"them: its `--` separator has to come before a script's own flags.",
								"",
								"    ${OsStr.display(script)} -- ${example}",
							],
							"\n",
						),
					)
				}
		}

	## Reject levels roc itself would reject, before any build starts.
	check_opt! = |opt|
		if ["speed", "dev", "interpreter", "size"].contains(opt) {
			Ok(opt)
		} else {
			fail!("invalid --opt=${opt}, expected speed, dev, interpreter or size")
		}
}
