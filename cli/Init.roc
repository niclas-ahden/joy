import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdout
import pf.Tty
import weaver.Cli
import weaver.Opt
import weaver.Param
import weaver.SubCmd
import Args
import Build
import Project
import Prompt
import Release
import Template

## `./joy init`: start a project from a template and install ./joy in it, or
## give a project that has an app already its ./joy.
Init :: [].{
	Options : { template : Try(Str, [NoValue]), no_input : Bool, non_empty : Bool, joy_checkout : Try(Str, [NoValue]), dir : Try(Str, [NoValue]) }

	## `./joy init` as a weaver subcommand, which also writes its --help.
	command : (Init.Options -> command) -> SubCmd.SubcommandParserConfig(command)
	command = |wrap|
		SubCmd.finish(
			{
				template: Opt.maybe_str({ short: "", long: "template", help: "The template to start from, without asking: ${names}." }),
				no_input: Opt.flag({ short: "", long: "no-input", help: "Never ask. Fail instead, and say which flag answers." }),
				non_empty: Opt.flag({ short: "", long: "non-empty", help: "Start in a folder that has files in it, without asking. Init never writes over them." }),
				joy_checkout: Opt.maybe_str({ short: "", long: "joy-checkout", help: "The Joy checkout the bundles build against. ($JOY_CHECKOUT)" }),
				dir: Param.maybe_str({ name: "dir", help: "Where to start the project, the current folder by default." }),
			}.Cli,
			{
				name: "init",
				description: "Start a project from a template, and install ./joy in it.",
				mapper: wrap,
			},
		)

	run! : Init.Options => Try({}, _)
	run! = |options| {
		# The checkout is found before moving into the project, since a path
		# to it is given from where init runs.
		named_checkout = checkout!(Args.given(options.joy_checkout))?
		own = own_program!()?
		dir =
			match Args.given(options.dir) {
				Some(given) => given.drop_suffix("/")
				None => "."
			}
		# A folder that does not exist yet is made only once a template is
		# chosen, so a cancelled init leaves nothing behind.
		existed = Path.utf8(dir).is_dir!() ?? False
		if existed {
			move_into!(dir)?
			{ bundles, .. } = Project.find!()?
			has_server =
				match Project.server!() {
					Some(_) => True
					None => False
				}
			if !bundles.is_empty() or has_server {
				ignore!([])?
				install!(own)?
				return Stdout.line!("This folder has a Joy app already, so init only installed ./joy.")
			}
			# A Roc download is often unpacked where the project starts.
			taken = (Path.utf8(".").list!() ?? []).map(|entry| Path.display(entry).drop_prefix("./")).drop_if(|name| name.starts_with(".") or name.starts_with("roc_nightly"))
			if !taken.is_empty() {
				start_beside!(dir, taken, options)?
			}
		}

		# A checkout, when one is named, wins over the release this CLI
		# belongs to. Installing ./joy beside an app needs neither.
		source =
			match Release.source(named_checkout) {
				Checkout(real) => Checkout(real)
				Published(release) => OnRelease(release)
				Unreleased => return Build.fail!("This CLI is not from a Joy release, so init needs a Joy checkout: --joy-checkout <dir>, or JOY_CHECKOUT.")
			}
		template = template!(options)?
		if existed {
			var $clashes = []
			for (file, _) in template.files {
				if Path.utf8(file).is_file!() ?? False {
					$clashes = $clashes.append(file)
				}
			}
			if !$clashes.is_empty() {
				return Build.fail!("${folder_name(dir)} has its own ${Str.join_with($clashes, ", ")}, which the ${template.name} template would write over. Move them aside, or start in a new folder: init my-app")
			}
		}
		if !existed {
			if Path.utf8(dir).create_all!().is_err() {
				return Build.fail!("Could not make the folder ${dir}.")
			}
			move_into!(dir)?
		}
		here = Path.display(Env.cwd!()?)
		install_command =
			match source {
				Checkout(checkout) => "roc run ${relative(here, "${checkout}/cli/main.roc")} init"
				OnRelease(release) => "roc run <cli url> init\n\nTake `<cli url>` from the notes of [Joy ${release.tag}](${release.notes_url})."
			}
		for (file, content) in template.files {
			folder = folder_of(file)
			platform_line =
				match source {
					Checkout(checkout) => "platform \"${relative("${here}/${folder}", "${checkout}/platform/main.roc")}\""
					OnRelease(release) => "platform \"${release.platform_url}\""
				}
			filled = content.replace_each(Template.platform_line, platform_line).replace_each(Template.install_command, install_command)
			if Path.utf8(folder).create_all!().is_err() {
				return Build.fail!("Could not make the folder ${folder}.")
			}
			if Path.utf8(file).write_utf8!(filled).is_err() {
				return Build.fail!("Could not write ${file}.")
			}
		}
		ignore!(template.ignored)?
		install!(own)?

		Stdout.line!("Started a project from the ${template.name} template, with ./joy to work on it.")?
		match source {
			Checkout(checkout) => Stdout.line!("Its bundles build against the Joy checkout at ${checkout}.\n")?
			OnRelease(release) => Stdout.line!("Its bundles are on Joy ${release.tag}.\n")?
		}
		if dir != "." {
			Stdout.line!("    cd ${dir}")?
		}
		Stdout.line!("    ./joy dev")
	}
}

names : Str
names = Str.join_with(Template.all.map(|template| template.name), ", ")

## The Joy checkout to build against, `given` or $JOY_CHECKOUT, as a real
## path, when one is named.
checkout! : [Some(Str), None] => Try([Some(Str), None], _)
checkout! = |given| {
	named =
		match given {
			Some(dir) => dir
			None =>
				match Env.var_str!(OsStr.from_str("JOY_CHECKOUT")) {
					Ok(dir) if dir != "" => dir
					_ => return Ok(None)
				}
		}
	real =
		match Path.utf8(named).canonicalize!() {
			Ok(path) => Path.display(path)
			Err(_) => return Build.fail!("There is no folder at ${named}.")
		}
	if !(Path.utf8("${real}/platform/main.roc").is_file!() ?? False) or !(Path.utf8("${real}/www/runtime.js").is_file!() ?? False) {
		return Build.fail!("${named} is not a Joy checkout: it needs platform/main.roc and www/runtime.js.")
	}
	Ok(Some(real))
}

## The template `--template` names, or the one the person picks. Without a
## terminal, with CI set or with --no-input, init never asks.
template! : Init.Options => Try(Template.Template, _)
template! = |options| {
	name =
		match Args.given(options.template) {
			Some(given) => given
			None =>
				if asks!(options.no_input) {
					choices = Template.all.map(|template| { name: template.name, description: template.description })
					match Prompt.choose!("What kind of app?", choices) {
						Ok(choice) => choice.name
						Err(_) => return Err(Exit(130))
					}
				} else {
					longest = Template.all.map(|template| template.name.count_utf8_bytes()).max() ?? 0
					listed = Template.all.map(|template| "  ${template.name}${Str.repeat(" ", longest - template.name.count_utf8_bytes())}  ${template.description}")
					return Build.fail!("Which template? Name one with --template:\n${Str.join_with(listed, "\n")}")
				}
		}
	match Template.all.find_first(|template| template.name == name) {
		Ok(found) => Ok(found)
		Err(_) => Build.fail!("There is no template called ${name}. The templates are ${names}.")
	}
}

## Whether to start the project in `dir`, which has the files `taken` in it.
## --non-empty answers yes. Without it, the person is asked, and where init
## never asks it refuses.
start_beside! : Str, List(Str), Init.Options => Try({}, _)
start_beside! = |dir, taken, options| {
	if options.non_empty {
		return Ok({})
	}
	found = described(folder_name(dir), taken)
	if !asks!(options.no_input) {
		return Build.fail!("${found}\nStart in an empty folder, name a new one (init my-app), or start here anyway with --non-empty.")
	}
	Stdout.line!(found)?
	choices = [
		{ name: "No", description: "Leave the folder as it is" },
		{ name: "Yes", description: "Start the project here, beside those files" },
	]
	match Prompt.choose!("Start the project here anyway?", choices) {
		Ok(choice) if choice.name == "Yes" => Ok({})
		Ok(_) => Err(Exit(1))
		Err(_) => Err(Exit(130))
	}
}

## What is in a folder that is not empty. A few files are listed one per
## line, more are not listed at all.
described : Str, List(Str) -> Str
described = |folder, taken|
	if taken.len() <= 5 {
		"${folder} has files in it already:\n${Str.join_with(taken.map(|name| "  ${name}"), "\n")}"
	} else {
		"${folder} has files in it already."
	}

folder_name : Str -> Str
folder_name = |dir| if (dir == ".") "This folder" else dir

expect described("busy", ["a", "b"]) == "busy has files in it already:\n  a\n  b"
expect described("busy", ["a", "b", "c", "d", "e", "f"]) == "busy has files in it already."

asks! : Bool => Bool
asks! = |no_input| {
	in_ci =
		match Env.var_str!(OsStr.from_str("CI")) {
			Ok(value) => value != ""
			Err(_) => False
		}
	!no_input and !in_ci and Tty.is_tty!()
}

## Keep ./joy, .joy/ and dist/ out of git, and `more`, what the template's
## own project leaves behind, adding what .gitignore lacks.
ignore! : List(Str) => Try({}, _)
ignore! = |more| {
	path = Path.utf8(".gitignore")
	current = path.read_utf8!() ?? ""
	present = current.split_on("\n").map(|line| line.trim())
	missing = ["/joy", "/.joy/", "/dist/"].concat(more).drop_if(|entry| present.contains(entry))
	if missing.is_empty() {
		return Ok({})
	}
	before = if (current.is_empty() or current.ends_with("\n")) "" else "\n"
	if path.write_utf8!("${current}${before}${Str.join_with(missing, "\n")}\n").is_err() {
		return Build.fail!("Could not write .gitignore.")
	}
	Ok({})
}

## Where ./joy comes from: this program's own file, or its source. With
## `roc run`, roc interprets the CLI through a stand-in that only works where
## roc put it, and names the source file as the program. With an --opt, roc
## builds the program it runs.
Own : [Program(Path.Path), Source(Str)]

own_program! : () => Try(Own, _)
own_program! = || {
	name =
		match Env.program_name!() {
			Ok(given) => OsStr.display(given)
			Err(_) => ""
		}
	if name.ends_with(".roc") {
		# A path from where init runs, kept whole before init moves into the
		# project.
		source = if (name.starts_with("/")) name else "${Path.display(Env.cwd!()?)}/${name}"
		return Ok(Source(source))
	}
	match Env.exe_path!() {
		Ok(path) => Ok(Program(path))
		Err(_) => Build.fail!("Could not find this program's own file to copy to ./joy.")
	}
}

## Put ./joy in place: a copy of the program, unless it is ./joy already, or
## a build of the source. --opt=dev builds in about a second, and ./joy
## spends its time waiting for roc's builds of the app either way. It is
## renamed into place, which works while the old ./joy runs.
install! : Own => Try({}, _)
install! = |own| {
	target = Path.utf8("joy")
	staged = Path.utf8(".joy.new")
	match own {
		Program(exe) => {
			same =
				match (exe.canonicalize!(), target.canonicalize!()) {
					(Ok(a), Ok(b)) => Path.display(a) == Path.display(b)
					_ => False
				}
			if same {
				return Ok({})
			}
			if exe.copy!(staged).is_err() or staged.rename!(target).is_err() {
				return Build.fail!("Could not copy ${Path.display(exe)} to ./joy.")
			}
			Ok({})
		}
		Source(source) => {
			_ = staged.delete!()
			built = Cmd.new(OsStr.from_str("roc")).args(["build", "--opt=dev", "--output=.joy.new", source].map(OsStr.from_str)).run!()
			if !(staged.is_file!() ?? False) {
				said =
					match built {
						Ok(output) => Str.from_utf8_lossy(output.stdout_bytes.concat(output.stderr_bytes))
						Err(err) => Str.inspect(err)
					}
				return Build.fail!("Could not build ./joy from ${source} with roc build --opt=dev:\n${said}")
			}
			if staged.rename!(target).is_err() {
				return Build.fail!("Could not move the built program to ./joy.")
			}
			Ok({})
		}
	}
}

move_into! : Str => Try({}, _)
move_into! = |dir|
	if Env.set_cwd!(Path.utf8(dir)).is_err() {
		Build.fail!("Could not move into ${dir}.")
	} else {
		Ok({})
	}

folder_of : Str -> Str
folder_of = |file|
	match file.split_last("/") {
		Ok({ before, .. }) => before
		Err(_) => "."
	}

## The path from the folder `from` to `to`, both absolute.
relative : Str, Str -> Str
relative = |from, to| {
	from_parts = from.split_on("/").drop_if(|part| part.is_empty() or part == ".")
	to_parts = to.split_on("/").drop_if(|part| part.is_empty())
	var $shared = 0
	while $shared < from_parts.len() and $shared < to_parts.len() and from_parts.get($shared) == to_parts.get($shared) {
		$shared = $shared + 1
	}
	"${Str.repeat("../", from_parts.len() - $shared)}${Str.join_with(to_parts.drop_first($shared), "/")}"
}

expect relative("/home/me/app/client", "/home/me/joy/platform/main.roc") == "../../joy/platform/main.roc"
expect relative("/home/me/app/client/.", "/home/me/joy/platform/main.roc") == "../../joy/platform/main.roc"
expect relative("/tmp/app/client", "/home/me/joy/platform/main.roc") == "../../../home/me/joy/platform/main.roc"
