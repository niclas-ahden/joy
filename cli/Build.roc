import pf.Cmd
import pf.Crypt
import pf.Env
import pf.Monotonic
import pf.OsStr
import pf.Path
import pf.Stderr
import pf.Stdout
import pf.System
import joy_runtime.JoyRuntime
import weaver.Cli
import weaver.Opt
import weaver.SubCmd
import Args
import Compile
import Generated
import HtmlPage
import JsonText
import Project
import Reference
import Script
import Stylesheet

## `./joy build`: what ships, into dist/ or `--out-dir`. The bundles go to
## client/ under hashed names with joy.js and runtime.js beside them, the
## server to server/main, and assets.json lists every name a page loads.
##
## The other functions here are shared with `./joy dev`.
Build :: [].{
	Options : { out_dir : Str, opt : Str, debug : Bool, jobs : Try(Str, [NoValue]), no_server : Bool, server_opt : Str, server_target : Try(Str, [NoValue]), public_dir : Str, client_url : Try(Str, [NoValue]), before : List(Str) }

	## `./joy build` as a weaver subcommand, which also writes its --help.
	command : (Build.Options -> command) -> SubCmd.SubcommandParserConfig(command)
	command = |wrap|
		SubCmd.finish(
			{
				out_dir: Opt.str({ short: "", long: "out-dir", help: "Write here instead of dist/, a directory inside the project.", default: Value("dist") }),
				opt: Opt.str({ short: "", long: "opt", help: "The bundles' roc --opt: size, speed or dev.", default: Value("size") }),
				debug: Opt.flag({ short: "", long: "debug", help: "The whole runtime, and roc's --debug." }),
				jobs: Opt.maybe_str({ short: "", long: "jobs", help: "Builds at a time, 4 by default." }),
				no_server: Opt.flag({ short: "", long: "no-server", help: "Build the bundles alone." }),
				server_opt: Opt.str({ short: "", long: "server-opt", help: "The server's roc --opt.", default: Value("speed") }),
				server_target: Opt.maybe_str({ short: "", long: "server-target", help: "Cross-compile the server, roc's --target." }),
				public_dir: Opt.str({ short: "", long: "public-dir", help: "The folder of files copied as they are.", default: Value("public") }),
				client_url: Opt.maybe_str({ short: "", long: "client-url", help: "Where the app serves client/, / by default. Stylesheets and pages in public/ get the hashed names of files below it too. ($JOY_CLIENT_URL)" }),
				before: Opt.str_list({ short: "", long: "before", help: "Run this command in a shell first, and stop if it fails, to compile what goes in assets/. Repeatable." }),
			}.Cli,
			{
				name: "build",
				description: "Build what ships into dist/: the bundles and assets/ under hashed names, public/, the server and assets.json. Anything after -- goes to roc.",
				mapper: wrap,
			},
		)

	## Build with `options`, and `roc` given to every roc build as it is.
	run! : Build.Options, List(Str) => Try({}, _)
	run! = |options, roc| {
		out = options.out_dir.drop_suffix("/")
		opt = options.opt
		server_opt = options.server_opt
		debug = options.debug
		jobs = parse_jobs!(Args.given(options.jobs))?
		started = Monotonic.now!()

		{ bundles, .. } = Project.find!()?
		server =
			if options.no_server {
				None
			} else {
				Project.server!()
			}
		if bundles.is_empty() and server == None {
			return fail!("There are no bundles under client/ and no server/main.roc, so there is nothing to build.")
		}
		check_releases!(bundles)?
		ensure_hosts!(bundles)?
		run_before!(options.before)?
		claim_output!(out, { debug, opt })?

		public_dir = options.public_dir.drop_suffix("/")
		# The hashes are of the source files, so the build's copy of
		# generated/ exists before anything compiles, and the server and the
		# bundles all build against it.
		client_url = client_url!(Args.given(options.client_url))
		{ names: assets, sheets } = hash_assets!(client_url)?
		public_files = files_below!(public_dir)?
		replace = generated_for_build!(out, bundles, assets, public_files, client_url)?

		server_jobs =
			match server {
				Some(file) => {
					Path.utf8("${out}/server").create_all!()?
					target =
						match options.server_target {
							Ok(given) => ["--target=${given}"]
							Err(NoValue) => []
						}
					args = ["build", "--opt=${server_opt}"].concat(target).concat(if (Generated.used_by!(file)) replace else []).concat(roc)
					[
						{
							name: "server",
							file,
							output: "${out}/server/${executable!("main")}",
							args,
							inputs: "",
							cache: Compile.server_cache(Compile.cache_root!(args)?, "server"),
							own_warnings_fail: True,
						},
					]
				}
				None => []
			}
		bundle_jobs = bundles.map_try!(
			|bundle| {
				Path.utf8("${out}/client/${bundle.id}").create_all!()?
				args = bundle_args(opt, debug, (if (Generated.used_by!(bundle.file)) replace else []).concat(roc))
				Ok({
					name: bundle.id,
					file: bundle.file,
					output: "${out}/client/${bundle.id}/app.wasm",
					args,
					inputs: "",
					cache: Compile.bundle_cache(Compile.cache_root!(args)?),
					own_warnings_fail: True,
				})
			},
		)?
		count = (server_jobs.len() + bundle_jobs.len()).to_str()
		Stdout.line!("Building ${count} at --opt=${opt}${if (server == None) "" else ", the server at --opt=${server_opt}"}, ${jobs.to_str()} at a time")?
		# The server starts first, since it is usually the longest build.
		results = Compile.run_all!(server_jobs.concat(bundle_jobs), jobs, report!)?
		failed = results.keep_if(|result| result.outcome == Failed)
		if !failed.is_empty() {
			return fail!("${failed.len().to_str()} of ${results.len().to_str()} builds failed, so ${out}/ is incomplete.")
		}

		names = name_bundles!(out, bundles)?
		wasms = names.map_try!(|(_, name)| Path.utf8("${out}/client/${name}").read_bytes!())?
		runtime = runtime!(bundles, if (debug) Full else Used(wasms))?
		# The runtime has to match the wasm, so joy.js imports it by a hashed
		# name, which no cache keeps past a deploy. runtime.js stays beside it
		# for pages that mount by hand.
		runtime_name = "runtime.${short_hash(Crypt.hash!(Str.to_utf8(runtime), Sha256))}.js"
		Path.utf8("${out}/client/runtime.js").write_utf8!(runtime)?
		Path.utf8("${out}/client/${runtime_name}").write_utf8!(runtime)?
		loader = shipped_loader!(bundles, debug)?.replace_each("'./runtime.js'", "'./${runtime_name}'").replace_each("\"./runtime.js\"", "\"./${runtime_name}\"")
		joy_name = "joy.${short_hash(Crypt.hash!(Str.to_utf8(loader), Sha256))}.js"
		Path.utf8("${out}/client/${joy_name}").write_utf8!(loader)?

		reserved = ["joy.js", "runtime.js", runtime_name, joy_name].concat(bundles.map(|bundle| "${bundle.id}/"))
		copy_assets!(out, reserved, assets, sheets)?
		public = copy_public!(out, public_dir, reserved.concat(assets.map(|(_, hashed)| hashed)), assets.map(|(plain, _)| plain), client_url, [("joy.js", joy_name)].concat(assets), names)?
		write_assets_json!(out, joy_name, runtime_name, names, assets, public)?
		write_marker!(out, { debug, opt, complete: True })?

		warn_about_paths!(assets.map(|(plain, _)| plain), public_dir, public_files, client_url)
		took = Monotonic.since(Monotonic.now!(), started)
		Stdout.line!("Built ${bundles.len().to_str()} bundle${plural(bundles.len())}${if (server == None) "" else " and the server"} into ${out}/ in ${seconds(took)}")
	}

	## Every file below `root`, by its path from `root`, links skipped.
	list_files! : Str => Try(List(Str), _)
	list_files! = |root| files_below!(root)

	## A command line as the user's shell would run it.
	shell! : Str => Cmd.Command
	shell! = |line|
		match System.target!().os() {
			Windows(_) => Cmd.new(OsStr.from_str("cmd")).args(["/C", line].map(OsStr.from_str))
			_ => Cmd.new(OsStr.from_str("sh")).args(["-c", line].map(OsStr.from_str))
		}

	## The roc flags of a bundle's build, with Joy's 1 MiB wasm stack.
	bundle_args : Str, Bool, List(Str) -> List(Str)
	bundle_args = |opt, debug, roc|
		["build", "--target=wasm32", "--opt=${opt}", "--wasm-stack-size=1048576"]
			.concat(if (debug) ["--debug"] else [])
			.concat(roc)

	## Bundles on different releases share one joy.js, so they must agree.
	check_releases! : List(Project.Bundle) => Try({}, _)
	check_releases! = |bundles| {
		releases = bundles.map_try!(|bundle| Ok((bundle, release_of!(bundle))))?
		distinct = releases.fold([], |seen, (_, release)| if (seen.contains(release)) seen else seen.append(release))
		if distinct.len() > 1 {
			lines = releases.map(|(bundle, release)| "  ${bundle.id}: ${release}")
			fail!(Str.join_with(["The bundles name different Joy releases, and they share one joy.js. Move them all to one:"].concat(lines), "\n"))
		} else {
			Ok({})
		}
	}

	## A checkout's wasm host, built when it is missing or older than its
	## source, the way the checkout's own build.roc builds it.
	ensure_hosts! : List(Project.Bundle) => Try({}, _)
	ensure_hosts! = |bundles| {
		checkouts = bundles.fold(
			[],
			|seen, bundle|
				match Project.checkout(bundle) {
					Some(dir) if !seen.contains(dir) => seen.append(dir)
					_ => seen
				},
		)
		checkouts.fold_try!({}, |_, checkout| ensure_host!(checkout))
	}

	## runtime.js: Joy's core with every feature, or with the features the
	## given wasm modules call.
	runtime! : List(Project.Bundle), [Full, Used(List(List(U8)))] => Try(Str, _)
	runtime! = |bundles, which| {
		written = www_of!(bundles)?
		www =
			match which {
				Full => written
				Used(_) => minified_or!(written)
			}
		core = Path.utf8("${www}/runtime.js").read_utf8!() ? |_| NoRuntime(www)
		features =
			(Path.utf8("${www}/features").list!() ?? [])
				.keep_if(|entry| Path.display(entry).ends_with(".js"))
				.map_try!(|entry| entry.read_utf8!())?
		made =
			match which {
				Full => JoyRuntime.full({ core, features })
				Used(wasms) => JoyRuntime.generate_all({ core, features, wasms })
			}
		match made {
			Ok(js) => Ok(js)
			Err(problem) => fail!("Could not put runtime.js together from ${www}: ${Str.inspect(problem)}")
		}
	}

	## The runtime.js ./joy dev serves: every feature, with hot reloading's additions
	## and, in a block of its own, its code and the port of the dev server.
	dev_runtime! : List(Project.Bundle), U16 => Try(Str, _)
	dev_runtime! = |bundles, port| {
		www = www_of!(bundles)?
		runtime = runtime!(bundles, Full)?
		missing = |_| NoRuntime("There is no hot reloading in ${www}. This Joy release is older than ./joy's.")
		seams = Path.utf8("${www}/hot-seams.js").read_utf8!() ? missing
		hot = Path.utf8("${www}/hot.js").read_utf8!() ? missing
		match JoyRuntime.hot({ runtime, seams }) {
			Ok(js) => Ok("${js}\n{\nconst JOY_DEV_PORT = ${port.to_str()};\n${hot}\n}\n")
			Err(problem) => fail!("Could not add hot reloading to runtime.js from ${www}: ${Str.inspect(problem)}")
		}
	}

	## A release's files, which roc fetches on the first build of an app on it.
	## ./joy dev reads them before it builds anything.
	fetch_release! : List(Project.Bundle) => Try({}, _)
	fetch_release! = |bundles| {
		first =
			match bundles {
				[bundle, ..] => bundle
				[] => return Ok({})
			}
		if Path.utf8(Project.www!(first)).is_dir!() ?? False {
			return Ok({})
		}
		Stdout.line!("Fetching Joy")?
		_ =
			Cmd.new(OsStr.from_str("roc"))
				.args(["check", first.file].map(OsStr.from_str))
				.env(OsStr.from_str("ROC_CACHE_DIR"), OsStr.from_str(".joy/roc-cache/fetch"))
				.run!()?
		if Path.utf8(Project.www!(first)).is_dir!() ?? False {
			Ok({})
		} else {
			fail!("Could not fetch ${first.joy}.")
		}
	}

	## joy.js, the loader that mounts every bundle root on a page.
	loader! : List(Project.Bundle) => Try(Str, _)
	loader! = |bundles| {
		www = www_of!(bundles)?
		match Path.utf8("${www}/joy.js").read_utf8!() {
			Ok(js) => Ok(js)
			Err(_) => fail!("There is no joy.js in ${www}. This Joy release is older than ./joy's loader.")
		}
	}

	## The loader a build ships.
	shipped_loader! : List(Project.Bundle), Bool => Try(Str, _)
	shipped_loader! = |bundles, debug| {
		written = www_of!(bundles)?
		www = if (debug) written else minified_or!(written)
		match Path.utf8("${www}/joy.js").read_utf8!() {
			Ok(js) => Ok(js)
			Err(_) => fail!("There is no joy.js in ${www}. This Joy release is older than ./joy's loader.")
		}
	}

	fail! : Str => Try(_ok, [Exit(I32)])
	fail! = |message| {
		Stderr.line!(message) ?? {}
		Err(Exit(1))
	}

	## Where the app serves client/: `given`, or $JOY_CLIENT_URL, or /, with a
	## slash at each end.
	client_url! : [Some(Str), None] => Str
	client_url! = |given| {
		value =
			match given {
				Some(url) => url
				None => Env.var_str!(OsStr.from_str("JOY_CLIENT_URL")) ?? "/"
			}
		"/${value.drop_prefix("/").drop_suffix("/")}/".replace_each("//", "/")
	}

	parse_jobs! : [Some(Str), None] => Try(U64, _)
	parse_jobs! = |given|
		match given {
			None => Ok(4)
			Some(text) =>
				match U64.from_str(text) {
					Ok(jobs) if jobs > 0 => Ok(jobs)
					_ => fail!("--jobs takes a number of builds to run at once, not ${text}.")
				}
		}

	## Print a finished build, with its log when it failed or warned.
	report! : Compile.Result => Try({}, _)
	report! = |result|
		match result.outcome {
			Built if result.warnings.is_empty() => Stdout.line!("  built ${result.job.name}")
			Built => Stdout.line!("  built ${result.job.name}, with warnings:\n${result.log}")
			Failed => Stderr.line!("  ${result.job.name} failed:\n${result.log}")
		}

	plural : U64 -> Str
	plural = |count| if (count == 1) "" else "s"

	seconds : _ -> Str
	seconds = |duration| {
		tenths = duration.to_millis() // 100
		"${(tenths // 10).to_str()}.${(tenths % 10).to_str()}s"
	}
}

## Run each --before command on the terminal. Before anything is built or
## emptied, so one that fails leaves the last build as it was.
run_before! : List(Str) => Try({}, _)
run_before! = |commands| {
	for command in commands {
		Stdout.line!("Running ${command}")?
		match Build.shell!(command).call!() {
			Ok({}) => {}
			Err(Interrupted) => return Err(Exit(130))
			Err(_) => return Build.fail!("--before failed, so nothing was built: ${command}")
		}
	}
	Ok({})
}

executable! : Str => Str
executable! = |name|
	match System.target!().os() {
		Windows(_) => "${name}.exe"
		_ => name
	}

## The release a bundle names, by where its runtime lives: a URL as written,
## a checkout by its real path.
release_of! : Project.Bundle => Str
release_of! = |bundle| {
	www = Project.www!(bundle)
	match Path.utf8(www).canonicalize!() {
		Ok(real) => Path.display(real)
		Err(_) => bundle.joy
	}
}

## The minified copies of `www` a release ships. A checkout has none, and gets
## the files as written.
minified_or! : Str => Str
minified_or! = |www|
	if Path.utf8("${www}/min/runtime.js").is_file!() ?? False "${www}/min" else www

www_of! : List(Project.Bundle) => Try(Str, _)
www_of! = |bundles|
	match bundles {
		[first, ..] => Ok(Project.www!(first))
		[] => Build.fail!("There are no bundles, so there is no Joy release to take the runtime from.")
	}

ensure_host! : Str => Try({}, _)
ensure_host! = |checkout| {
	source = Path.utf8("${checkout}/host/host.rs")
	if !(source.is_file!() ?? False) {
		return Ok({})
	}
	for (name, flags) in [("host", []), ("host-hot", ["--cfg", "joy_hot"])] {
		host = Path.utf8("${checkout}/platform/targets/wasm32/${name}.wasm")
		stale =
			match (host.time_modified!(), source.time_modified!()) {
				(Ok(built), Ok(changed)) => built.is_lt(changed)
				_ => True
			}
		if stale {
			Stdout.line!("Building Joy's wasm host ${name}.wasm in ${checkout}")?
			staged = "${checkout}/platform/targets/wasm32/${name}.wasm.joy-new"
			rustc = Env.var_str!("RUSTC") ?? "rustc"
			built =
				Cmd.new(OsStr.from_str(rustc))
					.args(
						["--edition", "2021", "--target", "wasm32-unknown-unknown", "--crate-type", "staticlib", "-C", "opt-level=2", "-C", "panic=abort", "--emit", "obj"]
							.concat(flags)
							.concat(["${checkout}/host/host.rs", "-o", staged])
							.map(OsStr.from_str),
					)
					.run!()?
			if built.status != Exited(0) {
				return Build.fail!("Building Joy's wasm host failed:\n${Str.from_utf8_lossy(built.stderr_bytes)}")
			}
			Path.utf8(staged).rename!(host)?
		}
	}
	Ok({})
}

## Take the output directory: only inside the project, never the project or
## a parent of it, and never one that holds files ./joy did not write.
claim_output! : Str, { debug : Bool, opt : Str } => Try({}, _)
claim_output! = |out, settings| {
	parts = out.split_on("/")
	if out.is_empty() or out == "." or out.starts_with("/") or out.contains("\\") or parts.contains("..") or parts.contains(".") {
		return Build.fail!("--out-dir must name a directory inside the project, not ${out}.")
	}
	dir = Path.utf8(out)
	if dir.exists!() ?? False {
		if !(dir.is_dir!() ?? False) {
			return Build.fail!("${out} is a file, not a directory.")
		}
		entries = dir.list!()?
		if !entries.is_empty() and !(Path.utf8("${out}/.joy-output").is_file!() ?? False) {
			return Build.fail!("${out}/ holds files ./joy did not write, so it will not empty it. Move them, or name another --out-dir.")
		}
		dir.delete_all!()?
	}
	Path.utf8("${out}/client").create_all!()?
	write_marker!(out, { debug: settings.debug, opt: settings.opt, complete: False })
}

## The marker says ./joy owns the directory, and how it was built, so a test
## harness can check it before it starts a browser.
write_marker! : Str, { debug : Bool, opt : Str, complete : Bool } => Try({}, _)
write_marker! = |out, { debug, opt, complete }|
	Path.utf8("${out}/.joy-output").write_utf8!(
		JsonText.object([
			("written_by", JsonText.string("./joy build")),
			("debug", if (debug) "true" else "false"),
			("opt", JsonText.string(opt)),
			("complete", if (complete) "true" else "false"),
		]),
	)

## Give each bundle's wasm its hashed name, and return the names by id.
name_bundles! : Str, List(Project.Bundle) => Try(List((Str, Str)), _)
name_bundles! = |out, bundles|
	bundles.map_try!(
		|bundle| {
			plain = Path.utf8("${out}/client/${bundle.id}/app.wasm")
			digest = Crypt.hash_file!(plain, Sha256)?
			name = "${bundle.id}/app.${short_hash(digest)}.wasm"
			plain.rename!(Path.utf8("${out}/client/${name}"))?
			Ok((bundle.id, name))
		},
	)

short_hash : Str -> Str
short_hash = |digest| Str.from_utf8(Str.to_utf8(digest).take_first(8)) ?? digest

## Each file in assets/, by its name and the name with a hash of its
## content that a build gives it, and the text of each stylesheet with the
## files it names given their hashed names. A stylesheet is hashed after
## those files, so a changed font gives the stylesheet that names it a new
## name too.
hash_assets! : Str => Try({ names : List((Str, Str)), sheets : List((Str, Str)) }, _)
hash_assets! = |client_url| {
	files = files_below!("assets")?
	var $names = []
	for file in files {
		if !file.ends_with(".css") {
			digest =
				match Crypt.hash_file!(Path.utf8("assets/${file}"), Sha256) {
					Ok(hash) => hash
					Err(err) => return Project.could_not!("read assets/${file}", err)
				}
			$names = $names.append((file, with_hash(file, short_hash(digest))))
		}
	}
	var $waiting = files.keep_if(|file| file.ends_with(".css")).map_try!(|file| read_text!("assets/${file}").map_ok(|text| (file, text)))?
	var $sheets = []
	while !$waiting.is_empty() {
		waiting = $waiting
		ready = waiting.keep_if(|(file, text)| Stylesheet.references(text, file, client_url).all(|named| !waiting.any(|(other, _)| other == named)))
		if ready.is_empty() {
			return Build.fail!("These stylesheets import each other in a circle, so none of them can be named after the others: ${Str.join_with(waiting.map(|(file, _)| "assets/${file}"), ", ")}")
		}
		for (file, text) in ready {
			rewritten = Stylesheet.rewrite(text, file, client_url, $names)
			$names = $names.append((file, with_hash(file, short_hash(Crypt.hash!(Str.to_utf8(rewritten), Sha256)))))
			$sheets = $sheets.append((file, rewritten))
		}
		$waiting = waiting.drop_if(|(file, _)| ready.any(|(done, _)| done == file))
	}
	names = $names
	Ok({ names: files.keep_oks(|file| names.find_first(|(plain, _)| plain == file)), sheets: $sheets })
}

## Write generated/ as the repository keeps it, with plain names, and the
## build's copy, with hashed ones, when a header names the package, and
## return the roc flags that build against the copy.
generated_for_build! : Str, List(Project.Bundle), List((Str, Str)), List(Str), Str => Try(List(Str), _)
generated_for_build! = |out, bundles, assets, public, client_url|
	if !Generated.named!()? {
		Ok([])
	} else {
		plain = generated_package!(bundles, assets.map(|(file, _)| (file, file)), public, client_url)?
		_ = Generated.write!("generated", plain)?
		hashed = generated_package!(bundles, assets, public, client_url)?
		_ = Generated.write!("${out}/generated", hashed)?
		root = Path.display(Env.cwd!()?)
		Ok(["--replace-dep", "${root}/generated/main.roc", "${root}/${out}/generated/main.roc"])
	}

generated_package! : List(Project.Bundle), List((Str, Str)), List(Str), Str => Try(List((Str, Str)), _)
generated_package! = |bundles, assets, public, client_url|
	match Generated.files(bundles, assets, public, client_url) {
		Ok(files) => Ok(files)
		Err(SameTag(one, other)) => Build.fail!("The bundles ${one} and ${other} would both be ${Project.tag_of(one)} in generated/Bundle.roc. Rename one of them.")
	}

## Warn about paths in scripts and stylesheets that will 404 from a build. An
## import between hashed files works in ./joy dev, which serves plain names, as
## a build leaves it as written. Only a stylesheet in assets/ has its paths
## rewritten. Files that are not UTF-8 are read as far as they can be, and one
## that cannot be read at all has already failed the build.
warn_about_paths! : List(Str), Str, List(Str), Str => {}
warn_about_paths! = |assets, public_dir, public_files, client_url| {
	kept = public_files.append("runtime.js")
	var $found = []
	for (dir, files) in [("assets", assets), (public_dir, public_files)] {
		for file in files {
			script = file.ends_with(".js") or file.ends_with(".mjs")
			if script or file.ends_with(".css") {
				text = Str.from_utf8_lossy(Path.utf8("${dir}/${file}").read_bytes!() ?? [])
				broken =
					if script {
						Reference.broken(Script.relative_imported(text), file, client_url, { kept, hashed: assets })
					} else if dir == "assets" {
						Reference.broken(Stylesheet.named(text), file, client_url, { kept: kept.concat(assets), hashed: [] })
					} else {
						Reference.broken(Stylesheet.named(text), file, client_url, { kept, hashed: assets })
					}
				verb = if (script) "imports" else "names"
				$found = $found.concat(broken.map(|(name, why)| ("  ${dir}/${file} ${verb} ${name}", why)))
			}
		}
	}
	if !$found.is_empty() {
		lines = $found.map(
			|(line, why)|
				match why {
					Hashed => "${line}, which a build gives a hashed name"
					Missing => "${line}, which is in neither assets/ nor ${public_dir}/"
				},
		)
		advice = if ($found.any(|(_, why)| why == Hashed)) ["Bundle the script into one file, or keep all of its modules in ${public_dir}/, which keeps its names."] else []
		Stderr.line!(Str.join_with(["Warning: these paths will 404 from a build:"].concat(lines).concat(advice), "\n")) ?? {}
	}
}

## Copy assets/ into client/ under the hashed names, each stylesheet as
## [hash_assets!] rewrote it.
copy_assets! : Str, List(Str), List((Str, Str)), List((Str, Str)) => Try({}, _)
copy_assets! = |out, reserved, assets, sheets|
	assets.fold_try!(
		{},
		|_, (file, hashed)| {
			if taken(reserved, hashed) {
				return Build.fail!("assets/${file} would be written to ${hashed}, which ./joy writes itself.")
			}
			destination = Path.utf8("${out}/client/${hashed}")
			create_parent!(destination)?
			match sheets.find_first(|(sheet, _)| sheet == file) {
				Ok((_, text)) => destination.write_utf8!(text)
				Err(_) => copy_file!("assets/${file}", destination)
			}
		},
	)

## Copy public/ into client/ byte for byte, apart from HTML, where the paths
## to the files in `renames` get the hashed names and each bundle root its
## wasm, see HtmlPage.
copy_public! : Str, Str, List(Str), List(Str), Str, List((Str, Str)), List((Str, Str)) => Try(List(Str), _)
copy_public! = |out, public_dir, reserved, asset_files, client_url, renames, names| {
	files = files_below!(public_dir)?
	files.fold_try!(
		{},
		|_, file| {
			if taken(reserved, file) {
				return Build.fail!("${public_dir}/${file} is at a path ./joy writes itself.")
			}
			if asset_files.contains(file) {
				return Build.fail!("${file} is in both ${public_dir}/ and assets/, and one would silently win.")
			}
			destination = Path.utf8("${out}/client/${file}")
			create_parent!(destination)?
			if file.ends_with(".html") or file.ends_with(".htm") {
				html = read_text!("${public_dir}/${file}")?
				destination.write_utf8!(HtmlPage.rewrite(html, file, client_url, renames, names))
			} else {
				copy_file!("${public_dir}/${file}", destination)
			}
		},
	)?
	Ok(files)
}

read_text! : Str => Try(Str, [Exit(I32)])
read_text! = |path|
	match Path.utf8(path).read_utf8!() {
		Ok(text) => Ok(text)
		Err(err) => Project.could_not!("read ${path}", err)
	}

copy_file! : Str, Path.Path => Try({}, [Exit(I32)])
copy_file! = |path, destination|
	match Path.utf8(path).copy!(destination) {
		Ok(_) => Ok({})
		Err(err) => Project.could_not!("copy ${path} to ${Path.display(destination)}", err)
	}

taken : List(Str), Str -> Bool
taken = |reserved, path| reserved.any(|name| if (name.ends_with("/")) path.starts_with(name) else path == name)

with_hash : Str, Str -> Str
with_hash = |file, short|
	match file.split_last(".") {
		Ok({ before, after }) if !before.ends_with("/") and !before.is_empty() => "${before}.${short}.${after}"
		_ => "${file}.${short}"
	}

create_parent! : Path => Try({}, _)
create_parent! = |file|
	match Path.display(file).split_last("/") {
		Ok({ before, .. }) => Path.utf8(before).create_all!()
		Err(_) => Ok({})
	}

## Every file below `root`, by its path from `root` in byte order, links
## skipped.
files_below! : Str => Try(List(Str), _)
files_below! = |root|
	if Path.utf8(root).is_dir!() ?? False {
		files_in!(root, "").map_ok(|files| files.sort_with(Project.order))
	} else {
		Ok([])
	}

files_in! : Str, Str => Try(List(Str), _)
files_in! = |root, prefix| {
	folder = if (prefix.is_empty()) root else "${root}/${prefix}"
	entries =
		match Path.utf8(folder).list!() {
			Ok(found) => found
			Err(err) => return Project.could_not!("read ${folder}/", err)
		}
	entries.fold_try!(
		[],
		|found, entry| {
			name =
				match Path.display(entry).split_last("/") {
					Ok({ after, .. }) => after
					Err(_) => Path.display(entry)
				}
			relative = if (prefix.is_empty()) name else "${prefix}/${name}"
			match entry.type!()? {
				IsDir => Ok(found.concat(files_in!(root, relative)?))
				IsFile => Ok(found.append(relative))
				_ => Ok(found)
			}
		},
	)
}

write_assets_json! : Str, Str, Str, List((Str, Str)), List((Str, Str)), List(Str) => Try({}, _)
write_assets_json! = |out, joy_name, runtime_name, names, assets, public| {
	json = JsonText.object([
		("roots", JsonText.object([("joy", JsonText.string("client")), ("assets", JsonText.string("client")), ("public", JsonText.string("client"))])),
		("joy", JsonText.string(joy_name)),
		("runtime", JsonText.string(runtime_name)),
		("bundles", JsonText.object(names.map(|(id, name)| (id, JsonText.string(name))))),
		("assets", JsonText.object(assets.map(|(plain, hashed)| (plain, JsonText.string(hashed))))),
		("public", JsonText.array(public.map(JsonText.string))),
	])
	Path.utf8("${out}/assets.json").write_utf8!("${json}\n")
}
