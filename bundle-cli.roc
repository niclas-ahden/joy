#!/usr/bin/env roc
# Run:
#
#   ./bundle-cli.roc --tag=0.36.0 --platform-url=<url> --notes-url=<url>
#
# To bundle ./joy's source into dist/cli/, ready to attach to the release
# whose platform is at --platform-url. `roc run --opt=speed <its url> init`
# then starts a project on that release. Run from the repo root.
#
# The bundle is a copy of cli/ with tools/runtime and the templates of
# examples/templates/ inside it, since a bundle holds one folder, and with
# cli/Release.roc naming the release, so init writes the release's platform
# URL into the projects it starts.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	weaver: "https://github.com/lukewilliamboswell/weaver/releases/download/0.10.2/7CdYzjBAJmprmnK45oTpmH6BXt76ZASN2Ck5uZQEoWsK.tar.zst",
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
	# Only the files Template.roc builds into ./joy. A template that was run
	# where it is holds a ./joy, builds and a database beside them.
	template_files = "sed -n 's|^import \\\"\\.\\./examples/\\(templates/[^\\\"]*\\)\\\" as .*|\\1|p' cli/Template.roc | while read -r file; do mkdir -p \"${stage}/$(dirname \"$file\")\" && cp \"examples/$file\" \"${stage}/$file\" || exit 1; done"
	run!("bash", ["-c", "cp cli/*.roc '${stage}/' && rm '${stage}/tests.roc' && cp -r cli/generated '${stage}/' && cp tools/runtime/*.roc '${stage}/runtime/' && ${template_files}"])?

	main_path = Path.utf8("${stage}/main.roc")
	main_source = main_path.read_utf8!() ?? fail!("could not read ${stage}/main.roc")?
	in_checkout = "joy_runtime: \"../tools/runtime/main.roc\""
	if !main_source.contains(in_checkout) {
		fail!("cli/main.roc no longer names ${in_checkout}, so the bundle would miss the runtime package")?
	}
	if main_source.contains("pf: platform \".") {
		fail!("cli/main.roc names its platform by a path, which only works beside a joy-cli-platform checkout. A release needs that platform's release URL there")?
	}
	main_path.write_utf8!(main_source.replace_each(in_checkout, "joy_runtime: \"runtime/main.roc\""))?

	template_path = Path.utf8("${stage}/Template.roc")
	template_source = template_path.read_utf8!() ?? fail!("could not read ${stage}/Template.roc")?
	in_checkout_templates = "import \"../examples/templates/"
	if !template_source.contains(in_checkout_templates) {
		fail!("cli/Template.roc no longer has ${in_checkout_templates}, so the bundle would miss the templates")?
	}
	template_path.write_utf8!(template_source.replace_each(in_checkout_templates, "import \"templates/"))?

	release = Path.utf8("${stage}/Release.roc")
	release_source = release.read_utf8!() ?? fail!("could not read ${stage}/Release.roc")?
	in_checkout_release = "current = Unreleased"
	if !release_source.contains(in_checkout_release) {
		fail!("cli/Release.roc no longer says ${in_checkout_release}, so the bundle would not know its release")?
	}
	named = "current = Published({ tag: \"${config.tag}\", platform_url: \"${config.platform_url}\", notes_url: \"${config.notes_url}\" })"
	in_checkout_version = "version = \"unreleased\""
	if !release_source.contains(in_checkout_version) {
		fail!("cli/Release.roc no longer says ${in_checkout_version}, so ./joy --version would not name its release")?
	}
	release.write_utf8!(release_source.replace_first(in_checkout_release, named).replace_first(in_checkout_version, "version = \"${config.tag}\""))?

	archive = bundle!("cd '${stage}' && roc bundle $(find . -type f | sed 's|^\\./||' | sort) --output-dir ..")?
	run!("rm", ["-rf", stage])?

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
