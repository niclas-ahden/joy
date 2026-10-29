import pf.Stderr
import pf.Stdout
import weaver.Cli

## Command-line parsing for ./joy's commands. Each command defines its options
## as a weaver parser, which also writes the command's --help. Everything
## after `--` goes to roc as it is, so it is split off before weaver reads the
## rest.
Args :: [].{

	## `args` before the first `--`, and the ones after it.
	split : List(Str) -> { own : List(Str), roc : List(Str) }
	split = |args|
		match args.find_first_index(|arg| arg == "--") {
			Ok(at) => { own: args.take_first(at), roc: args.drop_first(at + 1) }
			Err(_) => { own: args, roc: [] }
		}

	## Read a command's options. The help prints and exits 0, and a usage
	## error prints with the usage and exits 2.
	parse! : Cli.CliParser(config), List(Str) => Try(config, [Exit(I32)])
	parse! = |parser, args|
		match Cli.parse_or_display_message(parser, args, |arg| Utf8(arg)) {
			Ok(config) => Ok(config)
			Err(Help(message)) | Err(Version(message)) => {
				_ = Stdout.line!(message)
				Err(Exit(0))
			}
			Err(InvalidUsage(message)) => {
				_ = Stderr.line!(message)
				Err(Exit(2))
			}
		}

	## An option's value, when it was given.
	given : Try(Str, [NoValue]) -> [Some(Str), None]
	given = |value|
		match value {
			Ok(found) => Some(found)
			Err(NoValue) => None
		}
}

expect Args.split(["--jobs", "2", "--", "--debug", "x"]) == { own: ["--jobs", "2"], roc: ["--debug", "x"] }
expect Args.split(["--jobs", "2"]) == { own: ["--jobs", "2"], roc: [] }
