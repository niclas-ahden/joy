## ./joy, the command line every Joy project carries.
##
##     roc build --opt=speed cli/main.roc --output=<project>/joy
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	joy_runtime: "../tools/runtime/main.roc",
	pf: platform "https://github.com/growthagent/joy-cli-platform/releases/download/0.1.0-rc1/71QJT9cSt2W6XM4ovm4w6A2PAnq9uUpzn7jxT8PiTGqX.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.OsStr
import pf.Stdout
import weaver.Cli
import weaver.Opt
import weaver.SubCmd
import Args
import Build
import Dev
import Init
import JsonText
import Project

## What the command line asks for.
Command : [BuildCommand(Build.Options), DevCommand(Dev.Options), BundlesCommand({ json : Bool }), InitCommand(Init.Options)]

## ./joy's commands and their options, which also write every --help.
parser : Cli.CliParser(Command)
parser = Cli.assert_valid(
	Cli.finish(
		SubCmd.required([
			Dev.command(|options| DevCommand(options)),
			Build.command(|options| BuildCommand(options)),
			Init.command(|options| InitCommand(options)),
			SubCmd.finish(
				Cli.map(Opt.flag({ short: "", long: "json", help: "One JSON array, for scripts." }), |json| { json: json }),
				{
					name: "bundles",
					description: "List the bundles under client/: id, tag, file and output.",
					mapper: |options| BundlesCommand(options),
				},
			),
		]),
		{
			name: "joy",
			version: "",
			authors: [],
			description: "The command line of a Joy project. Run ./joy help <command>, or ./joy <command> --help, for a command's options.",
			text_style: Plain,
		},
	),
)

main! : List(OsStr) => Try({}, _)
main! = |raw_args| {
	{ own, roc } = Args.split(raw_args.map(OsStr.display))
	asked =
		match own {
			[] | ["help"] => ["--help"]
			["help", command] if ["dev", "build", "bundles", "init"].contains(command) => [command, "--help"]
			["help", .. as rest] => rest
			_ => own
		}
	match Args.parse!(parser, asked)? {
		DevCommand(options) => Dev.run!(options, roc)
		BuildCommand(options) => Build.run!(options, roc)
		BundlesCommand(options) => bundles!(options)
		InitCommand(options) => Init.run!(options)
	}
}

bundles! : { json : Bool } => Try({}, _)
bundles! = |options| {
	{ bundles, strays } = Project.find!()?
	if options.json {
		Stdout.line!(
			JsonText.array(
				bundles.map(
					|bundle|
						JsonText.object([
							("id", JsonText.string(bundle.id)),
							("tag", JsonText.string(bundle.tag)),
							("file", JsonText.string(bundle.file)),
							("output", JsonText.string("dist/client/${bundle.id}/")),
						]),
				),
			),
		)
	} else {
		if bundles.is_empty() {
			Stdout.line!("No bundles under client/.")?
		}
		for bundle in bundles {
			Stdout.line!("${bundle.id}  ${bundle.tag}  ${bundle.file}  dist/client/${bundle.id}/")?
		}
		for stray in strays {
			Stdout.line!("found, not built: ${stray}, a Joy app outside client/")?
		}
		Ok({})
	}
}
