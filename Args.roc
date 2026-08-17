import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import Util exposing [fail!]

## Argument parsing shared by the executable scripts in the repo root, built
## on weaver. Every script takes `--opt=<level>`, mirroring roc's own flag,
## and each level builds into its own build/<opt>/ tree.
Args :: [].{

	## The `--opt` option itself, one definition for every script's parser.
	## Required, weaver reports it when missing.
	opt_option = Opt.str({
		short: "",
		long: "opt",
		help: "Optimization level: speed, dev, interpreter or size.",
		default: NoDefault,
	})

	## Run a script's parser over its args. Help and version requests print
	## and exit zero, usage errors print and exit non-zero, so callers only
	## see a parsed config.
	parse! = |parser, args| {
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
				Err(Exit(1))
			}

			Ok(config) => Ok(config)
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
