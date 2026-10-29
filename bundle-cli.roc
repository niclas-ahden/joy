#!/usr/bin/env roc
# Run:
#
#   ./bundle-cli.roc --tag=0.36.0 --platform-url=<url> --notes-url=<url>
#
# To bundle ./joy's source into dist/cli/, ready to attach to the release
# whose platform is at --platform-url. `roc run --opt=speed <its url> init`
# then starts a project on that release. Run from the repo root.
#
# The bundle is a copy of cli/ with tools/runtime inside it, since a bundle
# holds one folder, and with cli/Release.roc naming the release, so init
# writes the release's platform URL into the projects it starts.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.9.0/7j6KBFBEZ8pNMLQHkx9xiwyZ2PmwQPgKNDPUih6gKe77.tar.zst",
}

import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stdout
import weaver.Cli
import weaver.Opt
import Args
import Util exposing [fail!, run!]

main! = |args| {
	config = Args.parse!(parser, args, "--tag=0.36.0 --platform-url=<url> --notes-url=<url>")?
	out = config.output_dir.drop_suffix("/")
	stage = "${out}/.cli"

	run!("rm", ["-rf", out])?
	run!("mkdir", ["-p", "${stage}/runtime"])?
	run!("bash", ["-c", "cp cli/*.roc '${stage}/' && rm '${stage}/tests.roc' && cp -r cli/generated cli/templates '${stage}/' && cp tools/runtime/*.roc '${stage}/runtime/'"])?

	main_path = Path.utf8("${stage}/main.roc")
	main_source = main_path.read_utf8!() ?? fail!("could not read ${stage}/main.roc")?
	in_checkout = "joy_runtime: \"../tools/runtime/main.roc\""
	if !main_source.contains(in_checkout) {
		fail!("cli/main.roc no longer names ${in_checkout}, so the bundle would miss the runtime package")?
	}
	main_path.write_utf8!(main_source.replace_each(in_checkout, "joy_runtime: \"runtime/main.roc\""))?

	release = Path.utf8("${stage}/Release.roc")
	release_source = release.read_utf8!() ?? fail!("could not read ${stage}/Release.roc")?
	in_checkout_release = "current = Unreleased"
	if !release_source.contains(in_checkout_release) {
		fail!("cli/Release.roc no longer says ${in_checkout_release}, so the bundle would not know its release")?
	}
	named = "current = Published({ tag: \"${config.tag}\", platform_url: \"${config.platform_url}\", notes_url: \"${config.notes_url}\" })"
	release.write_utf8!(release_source.replace_first(in_checkout_release, named))?

	# WORKAROUND: roc-lang/roc#12693 and #12701. A shared roc cache can crash
	# the check roc bundle runs. Drop the cache of its own when fixed.
	archive = bundle!("cd '${stage}' && ROC_CACHE_DIR=\"$PWD/../.roc-cache\" roc bundle $(find . -type f | sed 's|^\\./||' | sort) --output-dir ..")?
	run!("rm", ["-rf", stage, "${out}/.roc-cache"])?

	Stdout.line!("Bundled ./joy for ${config.tag} into ${out}/${archive}")
}

# Run a `roc bundle` command line via bash, returning the created archive's
# file name. roc bundle prints "Created: <path>" on success, so a missing
# line means it failed, whatever the exit code was.
bundle! = |command| {
	output = match Cmd.new(OsStr.from_str("bash")).args(["-c", command].map(OsStr.from_str)).run!() {
		Ok(ran) => Str.from_utf8_lossy(ran.stdout_bytes.concat(ran.stderr_bytes))
		Err(_) => fail!("could not run: ${command}")?
	}

	created = output.split_on("\n").keep_oks(|line| line.split_first("Created: ")).first()
	match created {
		Ok(split) =>
			match split.after.trim().split_last("/") {
				Ok(at_slash) => Ok(at_slash.after)
				Err(_) => Ok(split.after.trim())
			}

		Err(_) => {
			Stdout.line!(output)?
			fail!("no archive came out of: ${command}")
		}
	}
}

parser : Cli.CliParser({ tag : Str, platform_url : Str, notes_url : Str, output_dir : Str })
parser = Cli.assert_valid(
	Cli.finish(
		{
			tag: Opt.str({ short: "", long: "tag", help: "The release's tag.", default: NoDefault }),
			platform_url: Opt.str({ short: "", long: "platform-url", help: "The URL of the release's platform bundle.", default: NoDefault }),
			notes_url: Opt.str({ short: "", long: "notes-url", help: "The URL of the release's notes, which show the install command.", default: NoDefault }),
			output_dir: Opt.str({ short: "", long: "output-dir", help: "Where the bundle goes (default: dist/cli).", default: Value("dist/cli") }),
		}.Cli,
		{
			name: "bundle-cli",
			version: "",
			authors: [],
			description: "Bundle ./joy's source for a release.",
			text_style: Plain,
		},
	),
)
