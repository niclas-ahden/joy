#!/usr/bin/env roc
## The tests of ./joy. Each one makes a project in a temporary directory,
## runs ./joy in it, and checks what it printed, wrote and served.
##
## Run from the Joy repository's root:
##
##     roc cli/tests.roc                 # every test
##     roc cli/tests.roc dev             # the tests whose name contains "dev"
##
## ./joy is built at --opt=dev, as init builds it, or at $JOY_CLI_OPT.
##
## The tests run in six parts at once, or in as many as $JOY_TESTS_JOBS says.
## Each part is this program again with its share of the tests, and keeps a
## roc cache of its own for the run, as roc processes that write one cache at
## once can trip over each other.
##
## The bundles are built from Joy's platform in this checkout, so its wasm
## host must be built, and joy-html must be reachable or in roc's cache.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/niclas-ahden/joy-cli-platform/releases/download/0.1.0/2CA47UwgXEjGTSVAu1jBUqUNeJA23DLjQZTuwtyL6Zfu.tar.zst",
}

import pf.Cmd
import pf.Duration
import pf.Env
import pf.Http
import pf.Monotonic
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sleep
import pf.Stderr
import pf.Stdout
import http.Request
import http.Response

## A project to test in: where it is, where ./joy is, and where Joy is.
## `roc_cache` is the ROC_CACHE_DIR every ./joy run gets, one for each part of
## a run, so the builds stay warm across projects.
Ctx : { dir : Str, joy : Str, joy_root : Str, roc_cache : Str }

main! : List(OsStr) => Try({}, _)
main! = |args| {
	filter =
		match args.map(OsStr.display) {
			[given, ..] => given
			[] => ""
		}
	joy_root = Path.display(Env.cwd!()?)
	if !(Path.utf8("cli/main.roc").is_file!() ?? False) {
		Stderr.line!("Run the tests from the Joy repository's root.")?
		return Err(Exit(2))
	}
	# --opt=dev is what init installs. roc writes a program despite errors
	# and exits 0, so its summary decides.
	opt =
		match Env.var_str!(OsStr.from_str("JOY_CLI_OPT")) {
			Ok(given) if !given.is_empty() => given
			_ => "dev"
		}
	chosen = tests.keep_if(|(name, _)| name.contains(filter))
	joy = "${joy_root}/cli/target/joy"

	# One part of a run that main started: ./joy is built, and the tests are
	# every `count`-th one from `index` on.
	match Env.var_str!(OsStr.from_str("JOY_TESTS_PART")) {
		Ok(part) => {
			(index, count) =
				match part.split_first("/") {
					Ok({ before, after }) => (U64.from_str(before) ?? 0, U64.from_str(after) ?? 1)
					Err(_) => (0, 1)
				}
			mine = chosen.map_with_index(|test, at| (test, at)).keep_if(|(_, at)| at % count == index).map(|(test, _)| test)
			failed = run_tests!(mine, { joy, joy_root, roc_cache: "${joy_root}/cli/target/roc-cache-${index.to_str()}" })?
			if failed.is_empty() {
				return Ok({})
			} else {
				return Err(Exit(1))
			}
		}
		Err(_) => {}
	}

	Stdout.line!("Building ./joy at --opt=${opt}")?
	Path.utf8("cli/target").create_all!()?
	_ = Path.utf8("cli/target/joy").delete!()
	built = Cmd.new(OsStr.from_str("roc")).args(["build", "--opt=${opt}", "--output=cli/target/joy", "cli/main.roc"].map(OsStr.from_str)).run!()?
	said = Str.from_utf8_lossy(built.stdout_bytes.concat(built.stderr_bytes))
	if !(Path.utf8("cli/target/joy").is_file!() ?? False) or !said.contains("0 errors and ") {
		Stderr.line!(said)?
		return Err(Exit(1))
	}
	wanted =
		match Env.var_str!(OsStr.from_str("JOY_TESTS_JOBS")) {
			Ok(given) => U64.from_str(given) ?? 6
			Err(_) => 6
		}
	parts = if (wanted < chosen.len()) wanted else chosen.len()
	# Every project is in a folder roc has not seen, so a cache from an
	# earlier run only takes up room.
	for (_, index) in chosen.take_first(if (parts < 1) 1 else parts).map_with_index(|test, index| (test, index)) {
		Path.utf8("cli/target/roc-cache-${index.to_str()}").delete_all!() ?? {}
	}
	failed =
		if parts < 2 {
			run_tests!(chosen, { joy, joy_root, roc_cache: "${joy_root}/cli/target/roc-cache-0" })?
		} else {
			run_parts!(chosen.map(|(name, _)| name), filter, parts)?
		}
	if failed.is_empty() {
		Stdout.line!("All ${chosen.len().to_str()} tests passed")
	} else {
		Stdout.line!("${failed.len().to_str()} of ${chosen.len().to_str()} tests failed: ${Str.join_with(failed, ", ")}")?
		Err(Exit(1))
	}
}

## Run tests one after another, each in a folder of its own, and say how each
## went. Returns the names of the ones that failed.
run_tests! : List((Str, (Ctx => Try({}, [Failed(Str)])))), { joy : Str, joy_root : Str, roc_cache : Str } => Try(List(Str), _)
run_tests! = |chosen, { joy, joy_root, roc_cache }| {
	var $failed = []
	for (name, test!) in chosen {
		started = Monotonic.now!()
		# The real path: macOS keeps its temp dirs behind a symlink, and platform_from
		# counts the folders it climbs.
		outcome = Env.with_temp_dir!(|dir| test!({ dir: Path.display(dir.canonicalize!() ?? dir), joy, joy_root, roc_cache }))
		took = Monotonic.since(Monotonic.now!(), started).to_millis()
		match outcome {
			Ok({}) => Stdout.line!("ok    ${name} (${took.to_str()} ms)")?
			Err(CallbackErr(Failed(why))) => {
				Stdout.line!("FAIL  ${name}: ${why}")?
				$failed = $failed.append(name)
			}
			Err(other) => {
				Stdout.line!("FAIL  ${name}: ${Str.inspect(other)}")?
				$failed = $failed.append(name)
			}
		}
	}
	Ok($failed)
}

## Run the tests named `names` in `parts` parts at once, each this program
## again with JOY_TESTS_PART, and print what each said once it is done.
## Returns the names of the tests that failed or never ran.
run_parts! : List(Str), Str, U64 => Try(List(Str), _)
run_parts! = |names, filter, parts| {
	running = names.take_first(parts).map_with_index(|_, index| index).map_try!(
		|index|
			Cmd.new(OsStr.from_str("roc"))
				.args(["cli/tests.roc"].concat(if (filter == "") [] else [filter]).map(OsStr.from_str))
				.env(OsStr.from_str("JOY_TESTS_PART"), OsStr.from_str("${index.to_str()}/${parts.to_str()}"))
				.stdout(Capture)
				.stderr(Capture)
				.spawn_leashed!(),
	)?
	var $said = []
	for child in running {
		output = child.wait!()?
		heard = Str.from_utf8_lossy(output.stdout_bytes.concat(output.stderr_bytes)).trim()
		Stdout.line!(heard)?
		$said = $said.concat(heard.split_on("\n"))
	}
	# A part that stopped early leaves tests without a line.
	Ok(names.keep_if(|name| !$said.any(|line| line.starts_with("ok    ${name} ("))))
}

tests : List((Str, (Ctx => Try({}, [Failed(Str)]))))
tests = [
	("bundles finds apps by their headers", bundles_by_header!),
	("bundles names ids and tags by path", bundles_ids_and_tags!),
	("bundles lists Joy apps outside client/", bundles_strays!),
	("bundles --json", bundles_json!),
	("build writes hashed bundles, the loader, the runtime and assets.json", build_basic!),
	("build hashes stay the same for the same source", build_stable_hashes!),
	("build copies public/ and rewrites its HTML", build_public!),
	("build hashes assets/", build_assets!),
	("build names hashed files in stylesheets", build_stylesheet_urls!),
	("build warns about paths that will 404", build_broken_paths!),
	("build names a file it cannot read", build_unreadable!),
	("a folder outside client/ that cannot be read stops nothing", unreadable_elsewhere!),
	("build renames the paths a page names, and warns about the rest", build_page_paths!),
	("build without roc says so and keeps the last build", build_without_roc!),
	("a bundle whose name is no tag is refused in generated/", generated_not_a_tag!),
	("the guide's ./joy commands and flags exist", guide_flags!),
	("build runs Sass first with --before", sass_build!),
	("dev keeps Sass running with --watch", sass_watch!),
	("build runs esbuild first with --before, and esbuild minifies a build", esbuild_build!),
	("dev keeps esbuild running with --watch", esbuild_watch!),
	("build refuses a path that two things would take", build_conflicts!),
	("build guards --out-dir", build_out_dir_guards!),
	("build fails on a broken bundle and leaves no wasm", build_broken!),
	("build fails on a warning in the project's own files", build_own_warning!),
	("build --debug writes the whole runtime", build_debug!),
	("build refuses bundles on different releases", build_mixed_releases!),
	("build builds the server, and --no-server skips it", build_server!),
	("build builds a project that is a server alone", build_server_alone!),
	("build passes flags after -- to roc", build_roc_flags!),
	("build reports bad options, and help shows them all", build_bad_options!),
	("--version names the release, unreleased in a checkout", version!),
	("dev serves the pages of a project without a server", dev_serves_pages!),
	("dev rebuilds what a change reaches and tells the pages", dev_rebuilds!),
	("dev rebuilds every bundle a shared module reaches, and only those", dev_shared_module!),
	("dev tells a page that opened early when the first builds land", dev_early_page!),
	("dev survives a save while builds wait for their turn", dev_quick_saves!),
	("dev stops on Ctrl-C while the first builds run", dev_stopped_early!),
	("dev refuses to run twice in one project", dev_twice!),
	("dev keeps roc's report on the page when an older build lands after it", dev_broken_after_valid!),
	("dev builds a new bundle and forgets a removed one", dev_new_and_removed_bundles!),
	("dev reports changes in public/ and assets/", dev_assets!),
	("dev never fails on a warning", dev_warning!),
	("dev with --poll", dev_poll!),
	("dev takes the next port when one is taken", dev_next_port!),
	("dev starts, restarts and keeps the project's server", dev_server!),
	("dev with --no-server sends events only", dev_no_server!),
	("dev stops everything on Ctrl-C", dev_ctrl_c!),
	("dev runs --watch commands until it stops", dev_watch!),
	("dev recovers when --watch writes an asset after the first build", dev_watch_first_start!),
	("build runs --before commands, and stops when one fails", build_before!),
	("dev is the front door with --proxy", dev_front_door!),
	("dev answers 502 when a backend is down", dev_backend_down!),
	("dev answers for a server that is not up, and says when it is", dev_server_not_up!),
	("dev says when the server exits", dev_server_exits!),
	("dev refuses a malformed --proxy", dev_bad_proxy!),
	("dev serves folders with --mount and --mount-download", dev_mounts!),
	("build runs everything at once unless --jobs limits it", build_jobs!),
	("dev refuses a malformed --mount", dev_bad_mount!),
	("dev sends its events on a port of their own", dev_events_port!),
	("dev answers files while slow pages it forwarded are abandoned", dev_abandoned_pages!),
	("dev plays the proxy for a server that sits behind one", dev_behind_proxy!),
	("dev says when a server does not serve its files", dev_server_without_files!),
	("generated/ is written only when a header names it", generated_only_when_named!),
	("build compiles against hashed names and the server reads them", generated_build!),
	("a server refuses another build's assets.json", generated_refuses!),
	("a missing asset is a compile error", generated_missing_asset!),
	("two bundles with one tag are refused", generated_same_tag!),
	("dev rewrites generated/ when a file is added", generated_dev!),
	("init starts a project from a template, and the project builds", init_template!),
	("the other templates start projects that build too", init_other_templates!),
	("init asks before a folder with files, and skips dot files and Roc", init_folder_rules!),
	("init only installs ./joy where there is an app", init_existing_app!),
	("init never asks without a terminal, and needs a checkout", init_no_input!),
	("init run by roc builds ./joy from the source", init_interpreted!),
	("the README's example builds", readme_example!),
	("upgrade lists the releases to name where nobody can be asked", upgrade_no_input!),
	("upgrade moves the headers to a release and installs ./joy", upgrade_moves!),
	("upgrade hands the work to the ./joy of the release it moves to", upgrade_hands_off!),
	("upgrade refuses a checkout and an unknown release", upgrade_refuses!),
	("upgrade asks at a terminal, and a gap opens in place", upgrade_at_terminal!),
	("upgrade changes every file or none, and keeps their modes", upgrade_all_or_nothing!),
	("the guide's custom effects build, each with its JavaScript", guide_custom_effects!),
	("build ships the JavaScript of a package's custom effects, the ones an app calls", build_package_feature!),
	("a custom effect without its JavaScript fails the build, and the dev build", missing_effect!),
	("a project's module keeps the JavaScript of its custom effects beside it", project_feature!),
	("a custom effect is checked under any name, and so are its id's length and its section", effect_checks!),
	("dev builds again once a package that would not load is put right", dev_package_recovers!),
	("bundles share a module with a custom effect, side by side or through a package", shared_feature!),
]

# Fixtures

html_package = "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst"

## The platform of the fixture servers, the one ./joy is built on.
cli_platform = "https://github.com/niclas-ahden/joy-cli-platform/releases/download/0.1.0/2CA47UwgXEjGTSVAu1jBUqUNeJA23DLjQZTuwtyL6Zfu.tar.zst"

## A small Joy app that renders `label`, importing `imports`, with `extra`
## at the end of the file.
app_source : Str, Str, Str, Str -> Str
app_source = |platform_path, label, import_lines, extra|
	Str.join_with(
		[
			"app [Model, Msg, init, update, view, subscriptions] {",
			"\tpf: platform \"${platform_path}\",",
			"\thtml: \"${html_package}\",",
			"}",
			"",
			"import html.Html exposing [div, text]",
			"import pf.Effect",
			import_lines,
			"",
			"Model : {}",
			"",
			"Msg : [Nothing]",
			"",
			"subscriptions = |_model| []",
			"",
			"init : Str -> (Model, List(Effect(Msg)))",
			"init = |_| ({}, [])",
			"",
			"view : Model -> Html(Msg)",
			"view = |_model| div([], [text(${label})])",
			"",
			"update : Model, Msg -> (Model, List(Effect(Msg)))",
			"update = |model, _msg| (model, [])",
			extra,
		],
		"\n",
	)

## The path from `file`'s folder in the project to Joy's platform.
platform_from : Ctx, Str -> Str
platform_from = |ctx, file| {
	depth = "${ctx.dir}/${file}".split_on("/").drop_if(|part| part.is_empty()).len() - 1
	"${Str.repeat("../", depth)}${ctx.joy_root.drop_prefix("/")}/platform/main.roc"
}

## Write a bundle that renders `label`.
bundle! : Ctx, Str, Str => Try({}, [Failed(Str)])
bundle! = |ctx, file, label| write!(ctx, file, app_source(platform_from(ctx, file), "\"${label}\"", "", ""))

write! : Ctx, Str, Str => Try({}, [Failed(Str)])
write! = |ctx, file, content| {
	path = "${ctx.dir}/${file}"
	match path.split_last("/") {
		Ok({ before, .. }) => Path.utf8(before).create_all!() ? |_| Failed("could not make the folder of ${file}")
		Err(_) => {}
	}
	Path.utf8(path).write_utf8!(content).map_err(|_| Failed("could not write ${file}"))
}

read! : Ctx, Str => Try(Str, [Failed(Str)])
read! = |ctx, file| Path.utf8("${ctx.dir}/${file}").read_utf8!().map_err(|_| Failed("could not read ${file}"))

exists! : Ctx, Str => Bool
exists! = |ctx, file| Path.utf8("${ctx.dir}/${file}").exists!() ?? False

files_in! : Ctx, Str => List(Str)
files_in! = |ctx, dir|
	(Path.utf8("${ctx.dir}/${dir}").list!() ?? []).map(|entry| Path.display(entry).drop_prefix("${ctx.dir}/${dir}/"))

## A small server on joy-cli-platform that answers every request with
## `body`, on the port in $PORT, and prints what $JOY_ASSETS_JSON says.
server_source : Str -> Str
server_source = |body| server_answering(200, body)

## [server_source] with another status than 200.
server_answering : U16, Str -> Str
server_answering = |status, body| {
	Str.join_with(
		[
			"app [main!] {",
			"\thttp: \"https://github.com/roc-lang/http/releases/download/2.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst\",",
			"\tpf: platform \"${cli_platform}\",",
			"}",
			"",
			"import pf.Env",
			"import pf.OsStr",
			"import pf.Server",
			"import pf.Sleep",
			"import pf.Stdout",
			"import http.Response",
			"",
			"main! : List(OsStr) => Try({}, _)",
			"main! = |_args| {",
			"\tassets = Env.var_str!(OsStr.from_str(\"JOY_ASSETS_JSON\")) ?? \"unset\"",
			"\tport = U16.from_str(Env.var_str!(OsStr.from_str(\"PORT\")) ?? \"0\") ?? 0",
			"\tserver = Server.start!({ port: port }, |_| Ok(Server.respond(Response.from_status(${status.to_str()}).with_body(Str.to_utf8(\"${body}\")))))?",
			"\tStdout.line!(\"app listening on \${U16.to_str(server.port())} with \${assets}\")?",
			"\t_ = Sleep.millis!(1_000_000_000)",
			"\tServer.stop!(server)",
			"\tOk({})",
			"}",
		],
		"\n",
	)
}

# Running ./joy

Ran : { code : I32, out : Str }

run_joy! : Ctx, List(Str) => Try(Ran, [Failed(Str)])
run_joy! = |ctx, args| run_joy_with!(ctx, args, [])

## Run ./joy with `envs` added to its environment.
run_joy_with! : Ctx, List(Str), List((Str, Str)) => Try(Ran, [Failed(Str)])
run_joy_with! = |ctx, args, envs| {
	output =
		envs
			.fold(Cmd.new(OsStr.from_str(ctx.joy)).env(OsStr.from_str("ROC_CACHE_DIR"), OsStr.from_str(ctx.roc_cache)), |cmd, (key, value)| cmd.env(OsStr.from_str(key), OsStr.from_str(value)))
			.args(args.map(OsStr.from_str))
			.cwd(Path.utf8(ctx.dir))
			.stderr(MergeWithStdout)
			.timeout(Duration.minutes(5))
			.run!()
			? |err| Failed("./joy ${Str.join_with(args, " ")} did not run: ${Str.inspect(err)}")
	code =
		match output.status {
			Exited(exit) => exit
			Signaled(signal) => 128 + signal
		}
	Ok({ code, out: Str.from_utf8_lossy(output.stdout_bytes) })
}

## Run ./joy and require the exit code.
joy_ok! : Ctx, List(Str), I32 => Try(Str, [Failed(Str)])
joy_ok! = |ctx, args, expected| joy_with!(ctx, args, expected, [])

## [joy_ok!] with `envs` added to the environment.
joy_with! : Ctx, List(Str), I32, List((Str, Str)) => Try(Str, [Failed(Str)])
joy_with! = |ctx, args, expected, envs| {
	ran = run_joy_with!(ctx, args, envs)?
	if ran.code == expected {
		Ok(ran.out)
	} else {
		Err(Failed("./joy ${Str.join_with(args, " ")} exited ${ran.code.to_str()}, not ${expected.to_str()}:\n${ran.out}"))
	}
}

check : Bool, Str -> Try({}, [Failed(Str)])
check = |condition, why| if (condition) Ok({}) else Err(Failed(why))

contains : Str, Str -> Try({}, [Failed(Str)])
contains = |text, part| check(text.contains(part), "expected ${Str.inspect(part)} in:\n${text}")

lacks : Str, Str -> Try({}, [Failed(Str)])
lacks = |text, part| check(!text.contains(part), "did not expect ${Str.inspect(part)} in:\n${text}")

## The hashed wasm a build gave a bundle, from assets.json.
wasm_name! : Ctx, Str => Try(Str, [Failed(Str)])
wasm_name! = |ctx, id| {
	json = read!(ctx, "dist/assets.json")?
	match json.split_first("\"${id}\": \"") {
		Ok({ after, .. }) =>
			match after.split_first("\"") {
				Ok({ before, .. }) => Ok(before)
				Err(_) => Err(Failed("no wasm for ${id} in assets.json"))
			}
		Err(_) => Err(Failed("no wasm for ${id} in assets.json:\n${json}"))
	}
}

# ./joy bundles

bundles_by_header! : Ctx => Try({}, [Failed(Str)])
bundles_by_header! = |ctx| {
	# Comments before the header, and a header over several lines.
	write!(ctx, "client/commented.roc", "# A bundle\n## with comments\n\n${app_source(platform_from(ctx, "client/commented.roc"), "\"x\"", "", "")}")?
	bundle!(ctx, "client/plain.roc", "x")?
	# A module, an app on another platform and a dot folder are not bundles.
	write!(ctx, "client/Helper.roc", "Helper :: [].{\n\tlabel : Str\n\tlabel = \"x\"\n}\n")?
	write!(ctx, "client/other.roc", "app [main!] { pf: platform \"../somewhere/platform/main.roc\" }\n\nmain! = |_| Ok({})\n")?
	bundle!(ctx, "client/.hidden/secret.roc", "x")?
	out = joy_ok!(ctx, ["bundles"], 0)?
	contains(out, "commented  Commented  client/commented.roc  dist/client/commented/")?
	contains(out, "plain  Plain")?
	lacks(out, "Helper")?
	lacks(out, "other")?
	lacks(out, "secret")
}

bundles_ids_and_tags! : Ctx => Try({}, [Failed(Str)])
bundles_ids_and_tags! = |ctx| {
	bundle!(ctx, "client/Checkout/cart.roc", "cart")?
	bundle!(ctx, "client/Store/on_sale.roc", "on sale")?
	bundle!(ctx, "client/work-with-us.roc", "work")?
	out = joy_ok!(ctx, ["bundles"], 0)?
	contains(out, "Checkout/cart  CheckoutCart  client/Checkout/cart.roc  dist/client/Checkout/cart/")?
	contains(out, "Store/on_sale  StoreOnSale")?
	contains(out, "work-with-us  WorkWithUs")
}

bundles_strays! : Ctx => Try({}, [Failed(Str)])
bundles_strays! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	bundle!(ctx, "tests/fixture.roc", "fixture")?
	out = joy_ok!(ctx, ["bundles"], 0)?
	contains(out, "found, not built: tests/fixture.roc, a Joy app outside client/")?
	lacks(out, "fixture  Fixture")
}

bundles_json! : Ctx => Try({}, [Failed(Str)])
bundles_json! = |ctx| {
	bundle!(ctx, "client/Checkout/cart.roc", "cart")?
	out = joy_ok!(ctx, ["bundles", "--json"], 0)?
	contains(out, "[{ \"id\": \"Checkout/cart\", \"tag\": \"CheckoutCart\", \"file\": \"client/Checkout/cart.roc\", \"output\": \"dist/client/Checkout/cart/\" }]")?
	empty = joy_ok!({ ..ctx, dir: "${ctx.dir}/client/Checkout" }, ["bundles"], 0)?
	contains(empty, "No bundles under client/.")
}

# ./joy build

build_jobs! : Ctx => Try({}, [Failed(Str)])
build_jobs! = |ctx| {
	bundle!(ctx, "client/catalog.roc", "catalog")?
	bundle!(ctx, "client/cart.roc", "cart")?
	all = joy_ok!(ctx, ["build"], 0)?
	contains(all, "Building 2 at --opt=size")?
	check(!all.contains("at a time"), "a build without --jobs has a limit: ${all}")?
	limited = joy_ok!(ctx, ["build", "--jobs", "1"], 0)?
	contains(limited, ", 1 at a time")
}

build_basic! : Ctx => Try({}, [Failed(Str)])
build_basic! = |ctx| {
	bundle!(ctx, "client/catalog.roc", "catalog")?
	bundle!(ctx, "client/Checkout/cart.roc", "cart")?
	out = joy_ok!(ctx, ["build", "--jobs", "2"], 0)?
	contains(out, "Built 2 bundles into dist/")?
	catalog = wasm_name!(ctx, "catalog")?
	cart = wasm_name!(ctx, "Checkout/cart")?
	check(catalog.starts_with("catalog/app.") and catalog.ends_with(".wasm") and catalog != "catalog/app.wasm", "catalog's wasm is not hashed: ${catalog}")?
	check(exists!(ctx, "dist/client/${catalog}") and exists!(ctx, "dist/client/${cart}"), "the hashed wasm files are missing")?
	check(!exists!(ctx, "dist/client/catalog/app.wasm"), "the plain wasm name is left behind")?
	json = read!(ctx, "dist/assets.json")?
	contains(json, "\"roots\": { \"joy\": \"client\", \"assets\": \"client\", \"public\": \"client\" }")?
	loader = files_in!(ctx, "dist/client").keep_if(|name| name.starts_with("joy.") and name.ends_with(".js"))
	check(loader.len() == 1, "expected one hashed joy.js, found ${Str.inspect(loader)}")?
	contains(json, "\"joy\": \"${loader.first() ?? "?"}\"")?
	runtime = read!(ctx, "dist/client/runtime.js")?
	contains(runtime, "Features these apps use (see tools/runtime): none")?
	hashed_runtime = files_in!(ctx, "dist/client").keep_if(|name| name.starts_with("runtime.") and name != "runtime.js")
	check(hashed_runtime.len() == 1, "expected one hashed runtime, found ${Str.inspect(hashed_runtime)}")?
	runtime_name = hashed_runtime.first() ?? "?"
	contains(json, "\"runtime\": \"${runtime_name}\"")?
	contains(read!(ctx, "dist/client/${loader.first() ?? "?"}")?, "from './${runtime_name}'")?
	marker = read!(ctx, "dist/.joy-output")?
	contains(marker, "\"debug\": false")?
	contains(marker, "\"complete\": true")
}

build_stable_hashes! : Ctx => Try({}, [Failed(Str)])
build_stable_hashes! = |ctx| {
	bundle!(ctx, "client/app.roc", "same")?
	_ = joy_ok!(ctx, ["build"], 0)?
	first = wasm_name!(ctx, "app")?
	_ = joy_ok!(ctx, ["build"], 0)?
	second = wasm_name!(ctx, "app")?
	check(first == second, "the same source got two names: ${first} and ${second}")?
	bundle!(ctx, "client/app.roc", "different")?
	_ = joy_ok!(ctx, ["build"], 0)?
	third = wasm_name!(ctx, "app")?
	check(third != first, "a changed bundle kept its name ${first}")
}

build_public! : Ctx => Try({}, [Failed(Str)])
build_public! = |ctx| {
	bundle!(ctx, "client/catalog.roc", "catalog")?
	write!(ctx, "public/index.html", "<div data-joy-bundle=\"catalog\"></div>\n<script type=\"module\" src=\"./joy.js\"></script>\n")?
	write!(ctx, "public/docs/page.html", "<!-- <script src=\"../joy.js\"></script> -->\n<link rel=stylesheet href=/static/css/site.css>\n<link rel=\"stylesheet\" href=\"../css/site.css?v=2\">\n<div data-joy-bundle=\"catalog\"></div>\n<script type=\"module\" src=../joy.js></script>\n")?
	write!(ctx, "assets/css/site.css", "h1 { color: teal }\n")?
	write!(ctx, "public/robots.txt", "User-agent: *\n")?
	write!(ctx, "public/.well-known/security.txt", "Contact: x\n")?
	_ = joy_ok!(ctx, ["build", "--client-url", "/static"], 0)?
	wasm = wasm_name!(ctx, "catalog")?
	index = read!(ctx, "dist/client/index.html")?
	contains(index, "data-joy-bundle=\"catalog\" data-joy-wasm=\"${wasm}\"")?
	lacks(index, "\"./joy.js\"")?
	contains(index, "src=\"./joy.")?
	page = read!(ctx, "dist/client/docs/page.html")?
	contains(page, "data-joy-wasm=\"../${wasm}\"")?
	contains(page, "<!-- <script src=\"../joy.js\"></script> -->")?
	lacks(page, "src=../joy.js>")?
	css = files_in!(ctx, "dist/client/css").first() ?? "?"
	contains(page, "href=/static/css/${css}>")?
	contains(page, "href=\"../css/${css}?v=2\"")?
	robots = read!(ctx, "dist/client/robots.txt")?
	check(robots == "User-agent: *\n", "robots.txt changed on the way")?
	check(exists!(ctx, "dist/client/.well-known/security.txt"), "public/.well-known was not copied")?
	json = read!(ctx, "dist/assets.json")?
	contains(json, "\"public\": [")?
	contains(json, "\"robots.txt\"")
}

build_assets! : Ctx => Try({}, [Failed(Str)])
build_assets! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "assets/css/site.css", "h1 { color: teal }\n")?
	write!(ctx, "assets/fonts/hind", "not really a font")?
	_ = joy_ok!(ctx, ["build"], 0)?
	json = read!(ctx, "dist/assets.json")?
	css = files_in!(ctx, "dist/client/css")
	check(css.len() == 1 and (css.first() ?? "").starts_with("site.") and (css.first() ?? "").ends_with(".css") and css != ["site.css"], "site.css was not hashed: ${Str.inspect(css)}")?
	contains(json, "\"css/site.css\": \"css/${css.first() ?? "?"}\"")?
	copied = read!(ctx, "dist/client/css/${css.first() ?? "?"}")?
	check(copied == "h1 { color: teal }\n", "the hashed copy differs")?
	fonts = files_in!(ctx, "dist/client/fonts")
	check(fonts.len() == 1 and (fonts.first() ?? "").starts_with("hind."), "a file without an extension was not hashed: ${Str.inspect(fonts)}")
}

build_broken_paths! : Ctx => Try({}, [Failed(Str)])
build_broken_paths! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "assets/js/main.js", "import \"lit\"\n// import \"./commented.js\"\nimport \"./kept.js\"\nimport \"../runtime.js\"\n")?
	write!(ctx, "assets/css/site.css", "@import \"./base.css\";\na { background: url(../kept.png) } b { background: url(/server/route.png) }\n")?
	write!(ctx, "assets/css/base.css", "p {}\n")?
	write!(ctx, "public/js/kept.js", "import \"./other.js\"\n")?
	write!(ctx, "public/js/other.js", "export {}")?
	write!(ctx, "public/kept.png", "png")?
	quiet = joy_ok!(ctx, ["build"], 0)?
	check(!quiet.contains("Warning"), "a build warned about paths that work:\n${quiet}")?

	write!(ctx, "assets/js/main.js", "import{a}from\"./dep.js\";await import(`../lib/lazy.mjs`);import\"./typo.js\"")?
	write!(ctx, "assets/js/dep.js", "export const a = 1")?
	write!(ctx, "assets/lib/lazy.mjs", "import \"./gone.js\"")?
	write!(ctx, "assets/css/site.css", "@import \"./nope.css\";\na { background: url(gone.png) }\n")?
	write!(ctx, "public/js/kept.js", "import \"./dep.js\"\n")?
	write!(ctx, "public/js/page.css", "a { background: url(dep.js) }\n")?
	# Not UTF-8, which must not hide what the file imports.
	out = joy_ok!(ctx, ["build", "--before", "printf 'const s = \"\\351\";\\nimport \"./dep.js\"\\n' > assets/js/latin.js"], 0)?
	contains(out, "assets/js/main.js imports ./dep.js, which a build gives a hashed name")?
	contains(out, "assets/js/main.js imports ../lib/lazy.mjs, which a build gives a hashed name")?
	contains(out, "assets/js/main.js imports ./typo.js, which is in neither assets/ nor public/")?
	contains(out, "assets/lib/lazy.mjs imports ./gone.js, which is in neither assets/ nor public/")?
	contains(out, "assets/js/latin.js imports ./dep.js, which a build gives a hashed name")?
	contains(out, "assets/css/site.css names ./nope.css, which is in neither assets/ nor public/")?
	contains(out, "assets/css/site.css names gone.png, which is in neither assets/ nor public/")?
	contains(out, "public/js/kept.js imports ./dep.js, which a build gives a hashed name")?
	contains(out, "public/js/page.css names dep.js, which a build gives a hashed name")?
	contains(out, "keep all of its modules in public/")?
	check(files_in!(ctx, "dist/client/js").any(|name| name.starts_with("main.")), "the warning stopped the build")?

	write!(ctx, "assets/js/main.js", "import \"./typo.js\"")?
	write!(ctx, "assets/js/latin.js", "export {}")?
	write!(ctx, "assets/lib/lazy.mjs", "export {}")?
	write!(ctx, "assets/css/site.css", "a {}")?
	write!(ctx, "public/js/kept.js", "export {}")?
	write!(ctx, "public/js/page.css", "a {}")?
	missing = joy_ok!(ctx, ["build"], 0)?
	contains(missing, "assets/js/main.js imports ./typo.js")?
	check(!missing.contains("keep all of its modules"), "bundling was advised for a file that does not exist:\n${missing}")
}

build_unreadable! : Ctx => Try({}, [Failed(Str)])
build_unreadable! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	refused! = |path, want| {
		chmod!(ctx, "000", path)?
		ran = run_joy!(ctx, ["build"])?
		chmod!(ctx, "755", path)?
		check(ran.code == 1, "a build exited ${ran.code.to_str()} with ${path} unreadable:\n${ran.out}")?
		contains(ran.out, want)?
		check(!ran.out.contains("Program exited"), "a raw error reached the user:\n${ran.out}")
	}
	write!(ctx, "assets/locked.js", "export {}")?
	refused!("assets/locked.js", "Could not read assets/locked.js: permission denied")?
	write!(ctx, "assets/locked.css", "a {}")?
	refused!("assets/locked.css", "Could not read assets/locked.css: permission denied")?
	write!(ctx, "public/js/locked.js", "export {}")?
	refused!("public/js/locked.js", "Could not copy public/js/locked.js to dist/client/js/locked.js: permission denied")?
	write!(ctx, "public/page.html", "<p></p>")?
	refused!("public/page.html", "Could not read public/page.html: permission denied")?
	refused!("public/js", "Could not read public/js/: permission denied")
}

## A project can hold folders that are not ./joy's to read, a database's
## files say. Only client/, assets/ and public/ have to be read.
unreadable_elsewhere! : Ctx => Try({}, [Failed(Str)])
unreadable_elsewhere! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "pgdata/base/1", "rows")?
	chmod!(ctx, "000", "pgdata")?
	listed = run_joy!(ctx, ["bundles"])?
	built = run_joy!(ctx, ["build"])?
	chmod!(ctx, "755", "pgdata")?
	check(listed.code == 0 and listed.out.contains("app  App  client/app.roc"), "bundles stopped at an unreadable folder:\n${listed.out}")?
	check(built.code == 0, "a build stopped at an unreadable folder:\n${built.out}")
}

build_page_paths! : Ctx => Try({}, [Failed(Str)])
build_page_paths! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "assets/img/a.png", "png")?
	write!(ctx, "assets/css/site.css", "p {}")?
	write!(
		ctx,
		"public/index.html",
		Str.join_with(
			[
				"<meta property=\"og:image\" content=\"/img/a.png\">",
				"<style>body { background: url(/img/a.png) }</style>",
				"<img src=\"/img/a.png\" srcset=\"/img/a.png 1x, /img/a.png 2x\" style=\"mask: url(/img/a.png)\">",
				"<video poster=\"/img/a.png\"></video>",
				"<div data-background=\"/img/a.png\"></div>",
				"<script>fetch('/css/site.css')</script>",
				"<div data-joy-bundle=\"app\"></div><script type=\"module\" src=\"/joy.js\"></script>",
			],
			"\n",
		),
	)?
	out = joy_ok!(ctx, ["build"], 0)?
	page = read!(ctx, "dist/client/index.html")?
	hashed =
		match read!(ctx, "dist/assets.json")?.split_first("\"img/a.png\": \"") {
			Ok({ after, .. }) => "/${after.split_on("\"").first() ?? ""}"
			Err(_) => return Err(Failed("assets.json does not name img/a.png"))
		}
	check(page.split_on(hashed).len() - 1 == 7, "expected the hashed name ${hashed} 7 times in:\n${page}")?
	# What a build does not read stays as written, and the build says so.
	contains(page, "data-background=\"/img/a.png\"")?
	contains(page, "fetch('/css/site.css')")?
	contains(out, "Warning: these paths will 404 from a build:")?
	contains(out, "  public/index.html names /img/a.png where a build does not look, and gives the file a hashed name")?
	contains(out, "  public/index.html names /css/site.css where a build does not look, and gives the file a hashed name")
}

## Without roc nothing can build, and the last build is still there.
build_without_roc! : Ctx => Try({}, [Failed(Str)])
build_without_roc! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	_ = joy_ok!(ctx, ["build"], 0)?
	wasm = wasm_name!(ctx, "app")?
	out = joy_with!(ctx, ["build"], 1, [("PATH", "/nonexistent")])?
	contains(out, "./joy builds with roc, and there is no roc on the PATH.")?
	check(exists!(ctx, "dist/client/${wasm}"), "a build that could not start emptied dist/")?
	dev = joy_with!(ctx, ["dev", "--port", "0"], 1, [("PATH", "/nonexistent")])?
	contains(dev, "./joy builds with roc, and there is no roc on the PATH.")
}

## Fails unless `tool` can run, with where to get it.
needs_tool! : Str => Try({}, [Failed(Str)])
needs_tool! = |tool|
	if has_tool!(tool) {
		Ok({})
	} else {
		Err(Failed("${tool} is not on the PATH. The nix dev shell has it, and CI installs it."))
	}

chmod! : Ctx, Str, Str => Try({}, [Failed(Str)])
chmod! = |ctx, mode, path| {
	ran = Cmd.new(OsStr.from_str("chmod")).args([mode, path].map(OsStr.from_str)).cwd(Path.utf8(ctx.dir)).run!() ? |err| Failed("chmod: ${Str.inspect(err)}")
	check(ran.status == Exited(0), "chmod ${mode} ${path} failed")
}

has_tool! : Str => Bool
has_tool! = |tool|
	match Cmd.new(OsStr.from_str(tool)).args([OsStr.from_str("--version")]).run!() {
		Ok(output) => output.status == Exited(0)
		Err(_) => False
	}

## Nothing is still running the command `./joy dev` was given.
stopped! : Str => Try({}, [Failed(Str)])
stopped! = |command| {
	left = Cmd.new(OsStr.from_str("pgrep")).args(["-f", command].map(OsStr.from_str)).run!() ? |err| Failed("pgrep: ${Str.inspect(err)}")
	check(left.status == Exited(1), "${command} outlived ./joy dev:\n${Str.from_utf8_lossy(left.stdout_bytes)}")
}

## Wait for a file the project's watcher writes to say `text`.
file_says! : Ctx, Str, Str => Try({}, [Failed(Str)])
file_says! = |ctx, file, text| {
	var $tries = 0
	while $tries < 150 {
		if (read!(ctx, file) ?? "").contains(text) {
			return Ok({})
		}
		_ = Sleep.millis!(100)
		$tries = $tries + 1
	}
	Err(Failed("${file} never said ${text}: ${read!(ctx, file) ?? "(no such file)"}"))
}

## The one file in `folder` of the build with a hashed name after `stem`.
built_file! : Ctx, Str, Str => Try(Str, [Failed(Str)])
built_file! = |ctx, folder, stem| {
	match files_in!(ctx, folder).keep_if(|name| name.starts_with("${stem}.")) {
		[name] => read!(ctx, "${folder}/${name}")
		other => Err(Failed("expected one ${stem} in ${folder}, found ${Str.inspect(other)}"))
	}
}

guide_flags! : Ctx => Try({}, [Failed(Str)])
guide_flags! = |ctx| {
	commands = ["dev", "build", "bundles", "init"]
	helps = commands.map_try!(|command| joy_ok!(ctx, [command, "--help"], 0).map_ok(|help| (command, flags_in(help))))?
	topics = Path.utf8("${ctx.joy_root}/guide/Topic").list!() ? |_| Failed("could not list the guide's topics")
	var $checked = 0
	for topic in topics {
		source = topic.read_utf8!() ? |_| Failed("could not read ${Path.display(topic)}")
		var $in_shell = False
		for line in source.split_on("\n") {
			# A code block's language comes first, on a line of its own.
			trimmed = line.trim()
			if ["Sh,", "Roc,", "Js,", "Html,", "Text,"].contains(trimmed) {
				$in_shell = trimmed == "Sh,"
			}
			sample = $in_shell and trimmed.starts_with("\\\\")
			for after in line.split_on("./joy ").drop_first(1) {
				# A sample's quotes hold another tool's flags. Prose ends at its string's.
				words = (if (sample) outside_quotes(after) else after.split_on("\"").first() ?? after).split_on(" ")
				command = words.first() ?? ""
				match helps.find_first(|(name, _)| name == command) {
					Ok((_, help)) => {
						$checked = $checked + 1
						for word in words.drop_first(1) {
							name = word.split_on("=").first() ?? word
							if name.starts_with("--") and !help.contains(name) {
								return Err(Failed("${Path.display(topic)} has ./joy ${command} ${name}, which --help does not list"))
							}
						}
					}

					# A sample names a command. Prose can say anything.
					Err(_) if sample => return Err(Failed("${Path.display(topic)} has ./joy ${command}, which is no command: ${line.trim()}"))
					Err(_) => {}
				}
			}
		}
	}
	check($checked >= 3, "only ${$checked.to_str()} ./joy commands found in the guide")
}

## The flags a --help text lists, each whole, so `--prox` is not `--proxy`.
flags_in : Str -> List(Str)
flags_in = |help|
	help
		.replace_each("\n", " ")
		.split_on(" ")
		.map(|word| word.split_on("=").first() ?? word)
		.keep_if(|word| word.starts_with("--"))

## `text` without what its double quotes hold.
outside_quotes : Str -> Str
outside_quotes = |text| {
	var $outside = True
	var $kept = []
	for part in text.split_on("\"") {
		if $outside {
			$kept = $kept.append(part)
		}
		$outside = !$outside
	}
	Str.join_with($kept, " ")
}

sass_build! : Ctx => Try({}, [Failed(Str)])
sass_build! = |ctx| {
	needs_tool!("sass")?
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "styles/site.scss", "$accent: teal;\nh1 { color: $accent; }\n")?
	_ = joy_ok!(ctx, ["build", "--before", "sass --style=compressed --no-source-map styles:assets/css"], 0)?
	contains(read!(ctx, "assets/css/site.css")?, "color:teal")?
	contains(built_file!(ctx, "dist/client/css", "site")?, "color:teal")
}

sass_watch! : Ctx => Try({}, [Failed(Str)])
sass_watch! = |ctx| {
	needs_tool!("sass")?
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "styles/site.scss", "h1 { color: teal; }\n")?
	watch = "sass --watch styles:assets/css"
	dev = start_dev!(ctx, ["--watch", watch], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	file_says!(ctx, "assets/css/site.css", "teal")?
	write!(ctx, "styles/site.scss", "h1 { color: plum; }\n")?
	file_says!(ctx, "assets/css/site.css", "plum")?
	_ = stop_dev!(dev1)?
	stopped!(watch)
}

esbuild_build! : Ctx => Try({}, [Failed(Str)])
esbuild_build! = |ctx| {
	needs_tool!("esbuild")?
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "scripts/app.ts", "const greet = (who: string): string => \"hello \" + who\nconsole.log(greet(\"joy\"))\n")?
	_ = joy_ok!(ctx, ["build", "--before", "esbuild scripts/app.ts --bundle --minify --outfile=assets/app.js"], 0)?
	script = built_file!(ctx, "dist/client", "app")?
	contains(script, "hello")?
	check(!script.contains(": string"), "esbuild left TypeScript's types in:\n${script}")?

	# Minifying what a build wrote, which keeps each file's hashed name.
	write!(ctx, "assets/site.css", "a {\n  color: red;\n}\n")?
	_ = joy_ok!(ctx, ["build"], 0)?
	line = "esbuild \"dist/client/**/*.css\" --minify --outbase=dist/client --outdir=dist/client --allow-overwrite"
	ran = Cmd.new(OsStr.from_str("sh")).args(["-c", line].map(OsStr.from_str)).cwd(Path.utf8(ctx.dir)).stderr(MergeWithStdout).run!() ? |err| Failed("${line}: ${Str.inspect(err)}")
	check(ran.status == Exited(0), "${line}:\n${Str.from_utf8_lossy(ran.stdout_bytes)}")?
	css = built_file!(ctx, "dist/client", "site")?
	check(css.trim() == "a{color:red}", "esbuild did not minify the build: ${css}")
}

esbuild_watch! : Ctx => Try({}, [Failed(Str)])
esbuild_watch! = |ctx| {
	needs_tool!("esbuild")?
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "scripts/app.ts", "console.log(\"one\" as string)\n")?
	watch = "esbuild scripts/app.ts --bundle --outfile=assets/app.js --watch=forever"
	dev = start_dev!(ctx, ["--watch", watch], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	file_says!(ctx, "assets/app.js", "one")?
	write!(ctx, "scripts/app.ts", "console.log(\"two\" as string)\n")?
	file_says!(ctx, "assets/app.js", "two")?
	_ = stop_dev!(dev1)?
	stopped!(watch)
}

build_stylesheet_urls! : Ctx => Try({}, [Failed(Str)])
build_stylesheet_urls! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "assets/fonts/hind.woff2", "font one")?
	write!(ctx, "assets/css/base.css", "body { background: url('../images/bg.png?v=2') }\n")?
	write!(ctx, "assets/images/bg.png", "png")?
	write!(ctx, "assets/css/site.css", "@import \"base.css\";\n@font-face { src: url(\"../fonts/hind.woff2\") format(\"woff2\") }\na { b: url(/abs.png) } c { d: url(data:image/gif;base64,R0) } e { f: url(missing.png) }\n/* url(../images/bg.png) */ g { h: URL(/static/images/bg.png) } i { j: image-set(\"../images/bg.png\" 1x) } k { content: \"url(../images/bg.png)\" }\n")?
	_ = joy_with!(ctx, ["build"], 0, [("JOY_CLIENT_URL", "/static/")])?
	hashed! = |plain| {
		json = read!(ctx, "dist/assets.json")?
		match json.split_first("\"${plain}\": \"") {
			Ok({ after, .. }) => Ok(after.split_first("\"").map_ok(|{ before, .. }| before) ?? "?")
			Err(_) => Err(Failed("${plain} is not in assets.json"))
		}
	}
	font = hashed!("fonts/hind.woff2")?
	base = hashed!("css/base.css")?
	site = hashed!("css/site.css")?
	site_css = read!(ctx, "dist/client/${site}")?
	contains(site_css, "@import \"${base.drop_prefix("css/")}\";")?
	contains(site_css, "url(\"../${font}\") format(\"woff2\")")?
	contains(site_css, "url(/abs.png)")?
	contains(site_css, "url(data:image/gif;base64,R0)")?
	contains(site_css, "url(missing.png)")?
	contains(read!(ctx, "dist/client/${base}")?, "url('../${hashed!("images/bg.png")?}?v=2')")?
	background = hashed!("images/bg.png")?
	contains(site_css, "/* url(../images/bg.png) */")?
	contains(site_css, "URL(/static/${background})")?
	contains(site_css, "image-set(\"../${background}\" 1x)")?
	contains(site_css, "content: \"url(../images/bg.png)\"")?
	source = read!(ctx, "assets/css/site.css")?
	check(!source.contains(font), "the build changed the stylesheet in assets/")?
	# A changed font renames the stylesheet that names it, and not the others.
	write!(ctx, "assets/fonts/hind.woff2", "font two")?
	_ = joy_with!(ctx, ["build"], 0, [("JOY_CLIENT_URL", "/static/")])?
	check(hashed!("css/site.css")? != site, "site.css kept its name after the font it names changed")?
	check(hashed!("css/base.css")? == base, "base.css was renamed though nothing it names changed")?
	write!(ctx, "assets/css/base.css", "@import url(site.css);\n")?
	circle = joy_with!(ctx, ["build"], 1, [("JOY_CLIENT_URL", "/static/")])?
	contains(circle, "These stylesheets import each other in a circle")?
	contains(circle, "assets/css/base.css")?
	contains(circle, "assets/css/site.css")
}

build_conflicts! : Ctx => Try({}, [Failed(Str)])
build_conflicts! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "public/logo.svg", "<svg/>")?
	write!(ctx, "assets/logo.svg", "<svg/>")?
	both = joy_ok!(ctx, ["build"], 1)?
	contains(both, "logo.svg is in both public/ and assets/")?
	_ = Path.utf8("${ctx.dir}/assets/logo.svg").delete!()
	write!(ctx, "public/joy.js", "// mine")?
	loader = joy_ok!(ctx, ["build"], 1)?
	contains(loader, "public/joy.js is at a path ./joy writes itself")?
	_ = Path.utf8("${ctx.dir}/public/joy.js").delete!()
	write!(ctx, "public/app/notes.txt", "notes")?
	inside = joy_ok!(ctx, ["build"], 1)?
	contains(inside, "public/app/notes.txt is at a path ./joy writes itself")
}

build_out_dir_guards! : Ctx => Try({}, [Failed(Str)])
build_out_dir_guards! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	for dir in ["..", "../elsewhere", ".", "/tmp/joy-out", "out/../.."] {
		out = joy_ok!(ctx, ["build", "--out-dir", dir], 1)?
		contains(out, "--out-dir must name a directory inside the project")?
	}
	write!(ctx, "mine/notes.txt", "keep me")?
	refused = joy_ok!(ctx, ["build", "--out-dir", "mine"], 1)?
	contains(refused, "mine/ holds files ./joy did not write")?
	kept = read!(ctx, "mine/notes.txt")?
	check(kept == "keep me", "a refused build touched the directory")?
	# A directory ./joy wrote is emptied, so nothing stale survives.
	_ = joy_ok!(ctx, ["build", "--out-dir", "out/web"], 0)?
	write!(ctx, "out/web/client/stale.js", "old")?
	_ = joy_ok!(ctx, ["build", "--out-dir", "out/web"], 0)?
	check(!exists!(ctx, "out/web/client/stale.js"), "a stale file survived a rebuild")
}

build_broken! : Ctx => Try({}, [Failed(Str)])
build_broken! = |ctx| {
	bundle!(ctx, "client/good.roc", "good")?
	write!(ctx, "client/bad.roc", app_source(platform_from(ctx, "client/bad.roc"), "\"bad\"", "", "broken = "))?
	out = joy_ok!(ctx, ["build"], 1)?
	contains(out, "bad failed:")?
	contains(out, "1 of 2 builds failed")?
	contains(out, "built good")?
	check(!exists!(ctx, "dist/client/bad/app.wasm"), "a failed bundle left a wasm behind")?
	check(!exists!(ctx, "dist/assets.json"), "a failed build wrote assets.json")
}

build_own_warning! : Ctx => Try({}, [Failed(Str)])
build_own_warning! = |ctx| {
	write!(ctx, "client/app.roc", app_source(platform_from(ctx, "client/app.roc"), "\"app\"", "", "\nhelper = |n| {\n\tunused = 1\n\tn\n}\n"))?
	out = joy_ok!(ctx, ["build"], 1)?
	contains(out, "app failed:")?
	contains(out, "unused")
}

build_debug! : Ctx => Try({}, [Failed(Str)])
build_debug! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	_ = joy_ok!(ctx, ["build", "--debug"], 0)?
	runtime = read!(ctx, "dist/client/runtime.js")?
	contains(runtime, "Every feature, for development")?
	marker = read!(ctx, "dist/.joy-output")?
	contains(marker, "\"debug\": true")
}

build_mixed_releases! : Ctx => Try({}, [Failed(Str)])
build_mixed_releases! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "client/old.roc", app_source("https://github.com/niclas-ahden/joy/releases/download/0.1.0/Old.tar.zst", "\"old\"", "", ""))?
	out = joy_ok!(ctx, ["build"], 1)?
	contains(out, "The bundles name different Joy releases")?
	contains(out, "old: https://github.com/niclas-ahden/joy/releases/download/0.1.0/Old.tar.zst")?
	check(!exists!(ctx, "dist"), "a refused build wrote dist/")
}

build_server! : Ctx => Try({}, [Failed(Str)])
build_server! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", server_source("built"))?
	out = joy_ok!(ctx, ["build", "--server-opt", "dev"], 0)?
	contains(out, "Built 1 bundle and the server into dist/")?
	check(exists!(ctx, "dist/server/main"), "dist/server/main is missing")?
	_ = joy_ok!(ctx, ["build", "--no-server"], 0)?
	check(!exists!(ctx, "dist/server"), "--no-server built the server")?
	write!(ctx, "server/main.roc", "${server_source("built")}\nbroken = ")?
	failed = joy_ok!(ctx, ["build", "--server-opt", "dev"], 1)?
	contains(failed, "server failed:")
}

## A server that renders every page itself has no bundles, so its build has
## no loader and no runtime, and assets.json still names its assets.
build_server_alone! : Ctx => Try({}, [Failed(Str)])
build_server_alone! = |ctx| {
	write!(ctx, "server/main.roc", server_source("built"))?
	write!(ctx, "assets/css/site.css", "h1 { color: teal }\n")?
	write!(ctx, "public/robots.txt", "User-agent: *\n")?
	out = joy_ok!(ctx, ["build", "--server-opt", "dev"], 0)?
	contains(out, "Building the server at --opt=dev")?
	contains(out, "Built the server into dist/")?
	check(exists!(ctx, "dist/server/main"), "dist/server/main is missing")?
	check(exists!(ctx, "dist/client/robots.txt"), "public/ was not copied")?
	check(!exists!(ctx, "dist/client/runtime.js"), "a project without bundles got a runtime.js")?
	json = read!(ctx, "dist/assets.json")?
	contains(json, "\"bundles\": {}")?
	contains(json, "\"css/site.css\": \"css/site.")?
	marker = read!(ctx, "dist/.joy-output")?
	contains(marker, "\"complete\": true")
}

build_roc_flags! : Ctx => Try({}, [Failed(Str)])
build_roc_flags! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	_ = joy_ok!(ctx, ["build", "--", "--no-cache"], 0)?
	bad = joy_ok!(ctx, ["build", "--", "--no-such-roc-flag"], 1)?
	contains(bad, "app failed:")
}

build_bad_options! : Ctx => Try({}, [Failed(Str)])
build_bad_options! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	unknown = joy_ok!(ctx, ["build", "--fast"], 2)?
	contains(unknown, "The argument \"--fast\" was not recognized.")?
	missing = joy_ok!(ctx, ["build", "--opt"], 2)?
	contains(missing, "Option --opt expects a string.")?
	jobs = joy_ok!(ctx, ["build", "--jobs", "0"], 1)?
	contains(jobs, "--jobs takes a number")?
	command = joy_ok!(ctx, ["serve"], 2)?
	contains(command, "The subcommand \"serve\" was not recognized.")?
	for asked in [["help", "build"], ["build", "--help"]] {
		help = joy_ok!(ctx, asked, 0)?
		contains(help, "joy build")?
		contains(help, "--out-dir STR")?
		contains(help, "--public-dir STR")?
	}
	listed = joy_ok!(ctx, ["help"], 0)?
	for name in ["dev", "build", "bundles"] {
		contains(listed, "  ${name} ")?
	}
	_ = joy_ok!(ctx, ["help", "serve"], 2)?
	empty = joy_ok!({ ..ctx, dir: "${ctx.dir}/client" }, ["build"], 1)?
	contains(empty, "There are no bundles under client/ and no server/main.roc")
}

## A checkout's ./joy has no release, and bundle-cli.roc names it in the
## copy it bundles.
version! : Ctx => Try({}, [Failed(Str)])
version! = |ctx| {
	for asked in [["--version"], ["-V"]] {
		printed = joy_ok!(ctx, asked, 0)?
		check(printed.trim() == "unreleased", "./joy ${Str.join_with(asked, " ")} printed ${Str.inspect(printed)}")?
	}
	Ok({})
}

# ./joy dev

## A running ./joy dev, and what it has printed so far.
Dev : { child : Cmd.Child, out : Str }

start_dev! : Ctx, List(Str), List((Str, Str)) => Try(Dev, [Failed(Str)])
start_dev! = |ctx, args, envs| {
	child =
		Cmd.new(OsStr.from_str(ctx.joy))
			.args(["dev", "--jobs", "2"].concat(args).map(OsStr.from_str))
			.env(OsStr.from_str("ROC_CACHE_DIR"), OsStr.from_str(ctx.roc_cache))
			.envs(envs.map(|(name, value)| (OsStr.from_str(name), OsStr.from_str(value))))
			.cwd(Path.utf8(ctx.dir))
			.stdin(Null)
			.stdout(Pipe)
			.stderr(MergeWithStdout)
			.spawn_leashed!()
			? |err| Failed("./joy dev did not start: ${Str.inspect(err)}")
	Ok({ child, out: "" })
}

## Read what ./joy dev prints until `count` lines contain `part`.
wait_for! : Dev, Str, U64 => Try(Dev, [Failed(Str)])
wait_for! = |dev, part, count| {
	deadline = Monotonic.now!()
	var $out = dev.out
	while $out.split_on(part).len() - 1 < count {
		if Monotonic.since(Monotonic.now!(), deadline).to_millis() > 120_000 {
			return Err(Failed("./joy dev never printed ${Str.inspect(part)} ${count.to_str()} times:\n${$out}"))
		}
		match dev.child.read!(Duration.millis(200)) {
			Ok(Stdout(bytes)) | Ok(Stderr(bytes)) => {
				$out = Str.concat($out, Str.from_utf8_lossy(bytes))
			}
			Err(EndOfInput) => return Err(Failed("./joy dev exited:\n${$out}"))
			Err(_) => {}
		}
	}
	Ok({ ..dev, out: $out })
}

## Ctrl-C, and the output up to the end.
stop_dev! : Dev => Try(Str, [Failed(Str)])
stop_dev! = |dev| {
	pid = dev.child.pid()
	_ = Cmd.new(OsStr.from_str("kill")).args(["-INT", pid.to_str()].map(OsStr.from_str)).run!()
	var $out = dev.out
	var $reading = True
	while $reading {
		match dev.child.read!(Duration.seconds(10)) {
			Ok(Stdout(bytes)) | Ok(Stderr(bytes)) => {
				$out = Str.concat($out, Str.from_utf8_lossy(bytes))
			}
			_ => {
				$reading = False
			}
		}
	}
	_ = dev.child.close!()
	Ok($out)
}

## The port in a line ./joy dev printed, after `before`.
port_after : Str, Str -> Try(Str, [Failed(Str)])
port_after = |out, before|
	match out.split_first(before) {
		Ok({ after, .. }) => {
			digits = digits_of(Str.to_utf8(after), [])
			if digits.is_empty() {
				Err(Failed("no port after ${before}"))
			} else {
				Ok(Str.from_utf8(digits) ?? "")
			}
		}
		Err(_) => Err(Failed("./joy dev did not print ${Str.inspect(before)}:\n${out}"))
	}

## The digits at the start of `bytes`, after a colon or spaces.
digits_of : List(U8), List(U8) -> List(U8)
digits_of = |bytes, found|
	match bytes {
		[byte, .. as rest] if found.is_empty() and (byte == ':' or byte == ' ') => digits_of(rest, found)
		[byte, .. as rest] if byte >= '0' and byte <= '9' => digits_of(rest, found.append(byte))
		_ => found
	}

get! : Str => Try(Response, [Failed(Str)])
get! = |url| Http.send!(Request.from_method(GET).with_uri(url), {}).map_err(|err| Failed("GET ${url}: ${Str.inspect(err)}"))

body_of : Response -> Str
body_of = |response| Str.from_utf8_lossy(Response.body(response))

header_of : Response, Str -> Str
header_of = |response, name|
	match Response.headers(response).find_first(|header| header.name.caseless_ascii_equals(name)) {
		Ok(found) => found.value
		Err(_) => ""
	}

## An open event stream and the text it has sent so far.
Events : { response : Http.StreamingResponse, seen : Str }

listen! : Str => Try(Events, [Failed(Str)])
listen! = |port| {
	response =
		Http.send_streaming!(Request.from_method(GET).with_uri("http://localhost:${port}/.joy/events"), { idle_timeout: After(Duration.seconds(90)) })
			? |err| Failed("could not open the event stream: ${Str.inspect(err)}")
	Ok({ response, seen: "" })
}

## Read the stream until it has sent `count` events named `name`.
expect_event! : Events, Str, U64 => Try(Events, [Failed(Str)])
expect_event! = |events, name, count| {
	var $seen = events.seen
	while $seen.split_on("event: ${name}\n").len() - 1 < count {
		match Stream.next!(events.response.chunks()) {
			One({ item: Ok(chunk), .. }) => {
				$seen = Str.concat($seen, Str.from_utf8_lossy(chunk))
			}
			_ => return Err(Failed("the event stream ended before ${count.to_str()} ${name} events:\n${$seen}"))
		}
	}
	Ok({ ..events, seen: $seen })
}

dev_serves_pages! : Ctx => Try({}, [Failed(Str)])
dev_serves_pages! = |ctx| {
	bundle!(ctx, "client/catalog.roc", "catalog")?
	write!(ctx, "public/index.html", "<div data-joy-bundle=\"catalog\"></div><script type=\"module\" src=\"/joy.js\"></script>")?
	write!(ctx, "assets/css/site.css", "body {}")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built catalog", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	index = get!("http://localhost:${port}/")?
	contains(body_of(index), "data-joy-bundle=\"catalog\"")?
	check(header_of(index, "cache-control") == "no-cache", "pages are not served with Cache-Control: no-cache")?
	wasm = get!("http://localhost:${port}/catalog/app.wasm")?
	check(Response.status(wasm) == 200 and header_of(wasm, "content-type") == "application/wasm", "the wasm is not served as application/wasm")?
	loader = get!("http://localhost:${port}/joy.js")?
	contains(body_of(loader), "data-joy-bundle")?
	runtime = get!("http://localhost:${port}/runtime.js")?
	contains(body_of(runtime), "const JOY_DEV_PORT = ")?
	css = get!("http://localhost:${port}/css/site.css")?
	check(body_of(css) == "body {}", "assets/ is not served as it is")?
	spa = get!("http://localhost:${port}/books/7")?
	contains(body_of(spa), "data-joy-bundle=\"catalog\"")?
	missing = get!("http://localhost:${port}/missing.wasm")?
	check(Response.status(missing) == 404, "a missing file with an extension is not a 404")?
	assets = read!(ctx, ".joy/dev/assets.json")?
	contains(assets, "\"roots\": { \"joy\": \"client\", \"assets\": \"../../assets\", \"public\": \"../../public\" }")?
	contains(assets, "\"catalog\": \"catalog/app.wasm\"")?
	check(!exists!(ctx, "dist"), "./joy dev wrote dist/")?
	out = stop_dev!(dev1)?
	contains(out, "Stopped")
}

dev_rebuilds! : Ctx => Try({}, [Failed(Str)])
dev_rebuilds! = |ctx| {
	bundle!(ctx, "client/catalog.roc", "catalog")?
	bundle!(ctx, "client/cart.roc", "cart")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(wait_for!(dev, "built catalog", 1)?, "built cart", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	events = expect_event!(listen!(port)?, "hello", 1)?
	bundle!(ctx, "client/catalog.roc", "catalog, edited")?
	dev2 = wait_for!(dev1, "built catalog", 2)?
	events2 = expect_event!(events, "reload", 1)?
	contains(events2.seen, "event: reload\ndata: catalog\n")?
	# A reload names the build it brings a page to, the one a page that
	# connects now is greeted with, so a page that reconnects after taking
	# it in place knows it missed nothing.
	at_build =
		match events2.seen.split_first("event: reload\ndata: catalog\ndata: ") {
			Ok({ after, .. }) => after.split_on("\n").first() ?? ""
			Err(_) => return Err(Failed("a reload names no build:\n${events2.seen}"))
		}
	greeted = expect_event!(listen!(port)?, "hello", 1)?
	contains(greeted.seen, "event: hello\ndata: ${at_build}\n")?
	# A change outside the project's builds rebuilds nothing.
	write!(ctx, "README.md", "notes")?
	write!(ctx, "client/catalog.roc", app_source(platform_from(ctx, "client/catalog.roc"), "\"catalog\"", "", "broken = "))?
	dev3 = wait_for!(dev2, "catalog failed", 1)?
	events3 = expect_event!(events2, "failed", 1)?
	contains(events3.seen, "event: failed\ndata: catalog\ndata: ")?
	ok = get!("http://localhost:${port}/catalog/app.wasm")?
	check(Response.status(ok) == 200, "a failed build took away the last good wasm")?
	bundle!(ctx, "client/catalog.roc", "catalog, fixed")?
	dev4 = wait_for!(dev3, "built catalog", 2)?
	events4 = expect_event!(events3, "fixed", 1)?
	_ = expect_event!(events4, "reload", 2)?
	check(dev4.out.split_on("built cart").len() == 2, "an edit to catalog rebuilt cart:\n${dev4.out}")?
	_ = stop_dev!(dev4)?
	Ok({})
}

dev_shared_module! : Ctx => Try({}, [Failed(Str)])
dev_shared_module! = |ctx| {
	write!(ctx, "client/Shared.roc", "Shared :: [].{\n\tlabel : Str\n\tlabel = \"shared\"\n}\n")?
	write!(ctx, "client/one.roc", app_source(platform_from(ctx, "client/one.roc"), "Shared.label", "import Shared", ""))?
	write!(ctx, "client/two.roc", app_source(platform_from(ctx, "client/two.roc"), "Shared.label", "import Shared", ""))?
	bundle!(ctx, "client/three.roc", "alone")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(wait_for!(wait_for!(dev, "built one", 1)?, "built two", 1)?, "built three", 1)?
	write!(ctx, "client/Shared.roc", "Shared :: [].{\n\tlabel : Str\n\tlabel = \"shared, edited\"\n}\n")?
	dev2 = wait_for!(wait_for!(dev1, "built one", 2)?, "built two", 2)?
	check(dev2.out.split_on("built three").len() == 2, "a change to Shared.roc rebuilt three, which does not import it:\n${dev2.out}")?
	_ = stop_dev!(dev2)?
	Ok({})
}

## ./joy dev says where it is before it builds, so a page can open with no
## wasm to mount yet. It heard build 0 when it connected, and hears of build
## 1 when the first builds land.
dev_early_page! : Ctx => Try({}, [Failed(Str)])
dev_early_page! = |ctx| {
	for name in ["one", "two", "three", "four", "five", "six"] {
		bundle!(ctx, "client/${name}.roc", name)?
	}
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "Starting on", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	early = expect_event!(listen!(port)?, "hello", 1)?
	check(early.seen.trim().ends_with("-0"), "a page that opened before the first builds did not hear build 0:\n${early.seen}")?
	landed = expect_event!(early, "hello", 2)?
	check(landed.seen.trim().ends_with("-1"), "the first builds did not land as build 1:\n${landed.seen}")?
	dev2 = wait_for!(dev1, "built six", 1)?
	late = expect_event!(listen!(port)?, "hello", 1)?
	check(late.seen.trim().ends_with("-1"), "a page that opened after the first builds did not hear build 1:\n${late.seen}")?
	_ = stop_dev!(dev2)?
	Ok({})
}

## With --jobs a build can wait for its turn. A save that reaches it again
## while it waits must not start it twice, as both would write one file.
dev_quick_saves! : Ctx => Try({}, [Failed(Str)])
dev_quick_saves! = |ctx| {
	shared = |label| "Shared :: [].{\n\tlabel : Str\n\tlabel = \"${label}\"\n}\n"
	write!(ctx, "client/Shared.roc", shared("shared"))?
	for name in ["one", "two", "three"] {
		write!(ctx, "client/${name}.roc", app_source(platform_from(ctx, "client/${name}.roc"), "Shared.label", "import Shared", ""))?
	}
	dev = start_dev!(ctx, ["--port", "0"], [])?
	var $dev = wait_for!(wait_for!(wait_for!(dev, "built one", 1)?, "built two", 1)?, "built three", 1)?
	for round in [1, 2, 3, 4] {
		write!(ctx, "client/Shared.roc", shared("first save ${round.to_str()}"))?
		_ = Sleep.millis!(200)
		write!(ctx, "client/Shared.roc", shared("second save ${round.to_str()}"))?
		$dev = wait_for!($dev, "built three", round + 1)?
		_ = Sleep.millis!(1_500)
	}
	out = stop_dev!($dev)?
	lacks(out, "Program exited")?
	contains(out, "Stopped")
}

## Ctrl-C before the first builds are done stops ./joy dev as it does later.
dev_stopped_early! : Ctx => Try({}, [Failed(Str)])
dev_stopped_early! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	out = stop_dev!(wait_for!(dev, "Building", 1)?)?
	lacks(out, "Program exited")?
	contains(out, "Stopped")
}

## Two ./joy dev in one project would build into the same .joy/dev and
## serve each other's runtime, so the second says where the first is.
dev_twice! : Ctx => Try({}, [Failed(Str)])
dev_twice! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	runtime = read!(ctx, ".joy/dev/client/runtime.js")?
	second = joy_ok!(ctx, ["dev", "--port", "0"], 1)?
	contains(second, "./joy dev is already running in this project, on http://localhost:${port}/. Use that one, or stop it first.")?
	check(read!(ctx, ".joy/dev/client/runtime.js")? == runtime, "the second ./joy dev wrote over the first one's runtime.js")?
	wasm = get!("http://localhost:${port}/app/app.wasm")?
	check(Response.status(wasm) == 200, "the first ./joy dev stopped serving")?
	_ = stop_dev!(dev1)?
	# The port it wrote down answers no more, so the next one starts.
	again = start_dev!(ctx, ["--port", "0"], [])?
	again1 = wait_for!(again, "built app", 1)?
	_ = stop_dev!(again1)?
	Ok({})
}

## A save that builds, then one that does not, before the first has landed:
## the first build is of code the file no longer holds. Sending pages to it
## would take roc's report of the second off the page. So between the report
## and the build that fixes it, no page is told to reload.
dev_broken_after_valid! : Ctx => Try({}, [Failed(Str)])
dev_broken_after_valid! = |ctx| {
	bundle!(ctx, "client/catalog.roc", "catalog")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built catalog", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	events = expect_event!(listen!(port)?, "hello", 1)?
	var $dev = dev1
	var $events = events
	for round in [1, 2, 3] {
		bundle!(ctx, "client/catalog.roc", "catalog, saved ${round.to_str()}")?
		_ = Sleep.millis!(40)
		write!(ctx, "client/catalog.roc", app_source(platform_from(ctx, "client/catalog.roc"), "\"catalog\"", "", "broken = "))?
		$dev = wait_for!($dev, "catalog failed", round)?
		$events = expect_event!($events, "failed", round)?
		_ = Sleep.millis!(700)
		bundle!(ctx, "client/catalog.roc", "catalog, fixed ${round.to_str()}")?
		$events = expect_event!($events, "fixed", round)?
	}
	# Each report is followed by its fix, with nothing sending pages elsewhere
	# in between.
	for part in $events.seen.split_on("event: failed\n").drop_first(1) {
		while_broken = part.split_first("event: fixed\n").map_ok(|found| found.before) ?? part
		lacks(while_broken, "event: reload\n")?
	}
	_ = stop_dev!($dev)?
	Ok({})
}

dev_new_and_removed_bundles! : Ctx => Try({}, [Failed(Str)])
dev_new_and_removed_bundles! = |ctx| {
	bundle!(ctx, "client/first.roc", "first")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built first", 1)?
	bundle!(ctx, "client/Later/second.roc", "second")?
	dev2 = wait_for!(dev1, "built Later/second", 1)?
	check(exists!(ctx, ".joy/dev/client/Later/second/app.wasm"), "the new bundle's wasm is missing")?
	assets = read!(ctx, ".joy/dev/assets.json")?
	contains(assets, "\"Later/second\": \"Later/second/app.wasm\"")?
	_ = Path.utf8("${ctx.dir}/client/first.roc").delete!()
	dev3 = wait_for!(dev2, "first is no longer a bundle", 1)?
	check(!exists!(ctx, ".joy/dev/client/first"), "a removed bundle's wasm is still served")?
	_ = stop_dev!(dev3)?
	Ok({})
}

dev_assets! : Ctx => Try({}, [Failed(Str)])
dev_assets! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "public/index.html", "<p>one</p>")?
	write!(ctx, "assets/css/site.css", "body {}")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	events = expect_event!(listen!(port)?, "hello", 1)?
	write!(ctx, "assets/css/site.css", "body { margin: 0 }")?
	events2 = expect_event!(events, "asset", 1)?
	contains(events2.seen, "event: asset\ndata: css/site.css\n")?
	css = get!("http://localhost:${port}/css/site.css")?
	check(body_of(css) == "body { margin: 0 }", "the saved file is not served at once")?
	write!(ctx, "public/index.html", "<p>two</p>")?
	events3 = expect_event!(events2, "asset", 2)?
	contains(events3.seen, "event: asset\ndata: index.html\n")?
	_ = stop_dev!(dev1)?
	Ok({})
}

dev_warning! : Ctx => Try({}, [Failed(Str)])
dev_warning! = |ctx| {
	write!(ctx, "client/app.roc", app_source(platform_from(ctx, "client/app.roc"), "\"app\"", "", "\nhelper = |n| {\n\tunused = 1\n\tn\n}\n"))?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built app, with warnings", 1)?
	check(exists!(ctx, ".joy/dev/client/app/app.wasm"), "a bundle with a warning was not put in place")?
	_ = stop_dev!(dev1)?
	Ok({})
}

dev_poll! : Ctx => Try({}, [Failed(Str)])
dev_poll! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	dev = start_dev!(ctx, ["--port", "0", "--poll"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	bundle!(ctx, "client/app.roc", "app, edited")?
	dev2 = wait_for!(dev1, "built app", 2)?
	_ = stop_dev!(dev2)?
	Ok({})
}

dev_next_port! : Ctx => Try({}, [Failed(Str)])
dev_next_port! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	first = start_dev!(ctx, ["--port", "0"], [])?
	first1 = wait_for!(first, "Starting on", 1)?
	taken = port_after(first1.out, "Starting on http://localhost")?
	# Another project, so the two do not build into one .joy/.
	other = { ..ctx, dir: "${ctx.dir}/other" }
	bundle!(other, "client/app.roc", "other")?
	second = start_dev!(other, ["--port", taken], [])?
	second1 = wait_for!(second, "Starting on", 1)?
	next = port_after(second1.out, "Starting on http://localhost")?
	check(next != taken, "the second ./joy dev claims the taken port ${taken}")?
	_ = stop_dev!(second1)?
	_ = stop_dev!(first1)?
	Ok({})
}

dev_server! : Ctx => Try({}, [Failed(Str)])
dev_server! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", server_source("version one"))?
	dev = start_dev!(ctx, [], [("PORT", "0")])?
	dev1 = wait_for!(dev, "app listening on", 1)?
	contains(dev1.out, "with ${ctx.dir}/.joy/dev/assets.json")?
	dev_port = port_after(dev1.out, "The dev server sends events on http://localhost")?
	app_port = port_after(dev1.out, "[server] app listening on")?
	one = get!("http://localhost:${app_port}/")?
	check(body_of(one) == "version one", "the server answered ${body_of(one)}")?
	page = get!("http://localhost:${dev_port}/")?
	check(Response.status(page) == 404, "the dev server serves pages beside the project's server")?
	events = expect_event!(listen!(dev_port)?, "hello", 1)?
	write!(ctx, "server/main.roc", server_source("version two"))?
	dev2 = wait_for!(dev1, "app listening on", 2)?
	events2 = expect_event!(events, "server", 1)?
	contains(events2.seen, "data: server")?
	app_port2 = port_after(dev2.out.split_last("Started server").map_ok(|{ after, .. }| after) ?? dev2.out, "[server] app listening on")?
	two = get!("http://localhost:${app_port2}/")?
	check(body_of(two) == "version two", "the restarted server answered ${body_of(two)}")?
	write!(ctx, "server/main.roc", "${server_source("version three")}\nbroken = ")?
	dev3 = wait_for!(dev2, "server failed", 1)?
	still = get!("http://localhost:${app_port2}/")?
	check(body_of(still) == "version two", "a failed server build stopped the running server")?
	remembered = read!(ctx, ".joy/events-port")?
	check(remembered == dev_port, "the dev server's port was not remembered")?
	out = stop_dev!(dev3)?
	contains(out, "Stopped")?
	# The next run asks for the same dev server port first.
	again = start_dev!(ctx, [], [("PORT", "0")])?
	write!(ctx, "server/main.roc", server_source("version four"))?
	again1 = wait_for!(again, "The dev server sends events", 1)?
	check(port_after(again1.out, "The dev server sends events on http://localhost")? == dev_port, "the remembered port was not reused")?
	_ = stop_dev!(again1)?
	Ok({})
}

dev_no_server! : Ctx => Try({}, [Failed(Str)])
dev_no_server! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", server_source("never started"))?
	dev = start_dev!(ctx, ["--no-server"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	lacks(dev1.out, "Started server")?
	lacks(dev1.out, "Starting on")?
	port = port_after(dev1.out, "The dev server sends events on http://localhost")?
	events = expect_event!(listen!(port)?, "hello", 1)?
	_ = events
	_ = stop_dev!(dev1)?
	Ok({})
}

dev_ctrl_c! : Ctx => Try({}, [Failed(Str)])
dev_ctrl_c! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", server_source("running"))?
	dev = start_dev!(ctx, [], [("PORT", "0")])?
	dev1 = wait_for!(dev, "app listening on", 1)?
	app_port = port_after(dev1.out, "[server] app listening on")?
	out = stop_dev!(dev1)?
	contains(out, "Stopped")?
	match Http.send!(Request.from_method(GET).with_uri("http://localhost:${app_port}/"), {}) {
		Err(HttpErr(_)) => Ok({})
		other => Err(Failed("the project's server still answers after Ctrl-C: ${Str.inspect(other)}"))
	}
}

## A backend that answers every request with what it got, so a test can see
## what ./joy dev forwarded.
echo_backend! : Str => Try(Server, [Failed(Str)])
echo_backend! = |label|
	Server.start!(
		{ port: 0 },
		|request| {
			host = (Request.headers(request).find_first(|header| header.name.caseless_ascii_equals("host")) ?? { name: "host", value: "none" }).value
			text = "${label} ${Request.method_str(request)} ${Request.uri(request)} host=${host} body=${Str.from_utf8_lossy(Request.body(request))}"
			Ok(Server.respond(Response.from_status(200).with_body(Str.to_utf8(text))))
		},
	)
		.map_err(|err| Failed("the backend did not start: ${Str.inspect(err)}"))

dev_front_door! : Ctx => Try({}, [Failed(Str)])
dev_front_door! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "static/site.css", "body {}")?
	pages = echo_backend!("pages")?
	api = echo_backend!("api")?
	dev = start_dev!(
		ctx,
		[
			"--port",
			"0",
			"--client-url",
			"/static/",
			"--public-dir",
			"static",
			"--proxy",
			"/=http://127.0.0.1:${pages.port().to_str()}",
			"--proxy",
			"/api=http://127.0.0.1:${api.port().to_str()}",
		],
		[],
	)?
	dev1 = wait_for!(dev, "built app", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	page = get!("http://localhost:${port}/books/7?sort=new")?
	contains(body_of(page), "pages GET /books/7?sort=new host=localhost:${port}")?
	posted = Http.send!(Request.from_method(POST).with_uri("http://localhost:${port}/api/books").with_body(Str.to_utf8("title=Dune")), {}) ? |err| Failed("POST: ${Str.inspect(err)}")
	contains(body_of(posted), "api POST /api/books")?
	contains(body_of(posted), "body=title=Dune")?
	wasm = get!("http://localhost:${port}/static/app/app.wasm")?
	check(header_of(wasm, "content-type") == "application/wasm", "the dev build is not served under the client URL")?
	css = get!("http://localhost:${port}/static/site.css")?
	check(body_of(css) == "body {}", "the public folder is not served under the client URL")?
	missing = get!("http://localhost:${port}/static/missing.css")?
	contains(body_of(missing), "pages GET /static/missing.css")?
	events = expect_event!(listen!(port)?, "hello", 1)?
	_ = events
	_ = stop_dev!(dev1)?
	Server.stop!(pages)
	Server.stop!(api)
	Ok({})
}

dev_backend_down! : Ctx => Try({}, [Failed(Str)])
dev_backend_down! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	# A port that was free a moment ago, and nothing listens on now.
	gone = echo_backend!("gone")?
	closed = gone.port().to_str()
	Server.stop!(gone)
	dev = start_dev!(ctx, ["--port", "0", "--proxy", "/=http://127.0.0.1:${closed}"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	answer = get!("http://localhost:${port}/anything")?
	check(Response.status(answer) == 502, "a request for a backend that is down got ${Response.status(answer).to_str()}")?
	contains(body_of(answer), "./joy dev could not reach http://127.0.0.1:${closed}: client error (Connect). Is it running?")?
	# An event stream never ends, so it is refused instead of awaited.
	wants_stream = Request.from_method(GET).with_uri("http://localhost:${port}/events").with_headers([{ name: "Accept", value: "text/event-stream" }])
	stream = Http.send!(wants_stream, {}) ? |err| Failed("GET /events: ${Str.inspect(err)}")
	check(Response.status(stream) == 501, "an event stream through the front door got ${Response.status(stream).to_str()}")?
	contains(body_of(stream), "./joy dev does not pass an event stream through")?
	_ = stop_dev!(dev1)?
	Ok({})
}

## GET the way a browser opens a page.
open_page! : Str => Try(Response, [Failed(Str)])
open_page! = |url|
	Http.send!(Request.from_method(GET).with_uri(url).with_headers([{ name: "Accept", value: "text/html,*/*" }]), {})
		.map_err(|err| Failed("GET ${url}: ${Str.inspect(err)}"))

## Wait for the page at `url` to say `text`.
page_says! : Str, Str => Try(Response, [Failed(Str)])
page_says! = |url, text| {
	var $tries = 0
	while $tries < 150 {
		page = open_page!(url)?
		if body_of(page).contains(text) {
			return Ok(page)
		}
		_ = Sleep.millis!(100)
		$tries = $tries + 1
	}
	Err(Failed("${url} never said ${text}: ${body_of(open_page!(url)?)}"))
}

dev_server_not_up! : Ctx => Try({}, [Failed(Str)])
dev_server_not_up! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", "${server_source("version one")}\nbroken = ")?
	dev = start_dev!(ctx, ["--port", "0"], [("JOY_SERVE_FILES", "1")])?
	dev1 = wait_for!(dev, "Building 2,", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	url = "http://localhost:${port}/books"

	# While it builds a page says how far the builds are, and asks again.
	building = page_says!(url, " of 2 done")?
	check(Response.status(building) == 503, "a page during the builds got ${Response.status(building).to_str()}")?
	check(header_of(building, "content-type").contains("text/html"), "a page during the builds is not HTML")?
	contains(body_of(building), "http-equiv=\"refresh\"")?
	contains(body_of(building), "could not reach")?
	lacks(body_of(building), "[99")?

	# A server that does not build says so.
	broken = page_says!(url, "The server did not build")?
	check(Response.status(broken) == 503, "a page without a server got ${Response.status(broken).to_str()}")?
	dev2 = wait_for!(dev1, "built app", 1)?
	lacks(dev2.out, "Ready on")?

	# A request that is not a page gets the same words, without the document.
	plain = get!(url)?
	check(Response.status(plain) == 503, "a request without a server got ${Response.status(plain).to_str()}")?
	contains(body_of(plain), "The server did not build")?
	contains(body_of(plain), "could not reach")?
	lacks(body_of(plain), "<html")?

	# Once it builds and answers, the pages are ready, and only then.
	write!(ctx, "server/main.roc", server_source("version one"))?
	dev3 = wait_for!(dev2, "Ready on http://localhost:${port}/", 1)?
	page = open_page!(url)?
	check(Response.status(page) == 200 and body_of(page) == "version one", "a ready page got ${Response.status(page).to_str()}: ${body_of(page)}")?
	_ = stop_dev!(dev3)?
	Ok({})
}

dev_server_exits! : Ctx => Try({}, [Failed(Str)])
dev_server_exits! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", "app [main!] { pf: platform \"${cli_platform}\" }\n\nimport pf.OsStr\n\nmain! : List(OsStr) => Try({}, _)\nmain! = |_args| Ok({})\n")?
	dev = start_dev!(ctx, ["--port", "0"], [("JOY_SERVE_FILES", "1")])?
	dev1 = wait_for!(dev, "server exited", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	lacks(dev1.out, "Ready on")?
	gone = page_says!("http://localhost:${port}/", "The server exited. ./joy starts it again after the next build.")?
	check(Response.status(gone) == 503, "a page after the server exited got ${Response.status(gone).to_str()}")?
	_ = stop_dev!(dev1)?
	Ok({})
}

dev_bad_proxy! : Ctx => Try({}, [Failed(Str)])
dev_bad_proxy! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	out = joy_ok!(ctx, ["dev", "--proxy", "api=localhost:3000"], 1)?
	contains(out, "--proxy takes PATH=URL")
}

dev_mounts! : Ctx => Try({}, [Failed(Str)])
dev_mounts! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "media/film.mp4", "film bytes")?
	write!(ctx, "secret.txt", "not served")?
	pages = echo_backend!("pages")?
	dev = start_dev!(
		ctx,
		["--port", "0", "--proxy", "/=http://127.0.0.1:${pages.port().to_str()}", "--mount", "/videos=media", "--mount", "/later=not/there/yet"],
		[("JOY_MOUNT", "/env=media"), ("JOY_MOUNT_DOWNLOAD", "/download/videos=media")],
	)?
	dev1 = wait_for!(dev, "built app", 1)?
	contains(dev1.out, "the files under /videos from media")?
	port = port_after(dev1.out, "Starting on http://localhost")?
	base = "http://localhost:${port}"

	film = get!("${base}/videos/film.mp4")?
	check(Response.status(film) == 200 and body_of(film) == "film bytes", "a mount did not serve its file: ${body_of(film)}")?
	check(header_of(film, "content-disposition") == "", "--mount answered with a download")?
	from_env = get!("${base}/env/film.mp4")?
	check(body_of(from_env) == "film bytes", "JOY_MOUNT did not serve its file: ${body_of(from_env)}")?

	# A video player asks for parts of the file, to seek.
	part = Http.send!(Request.from_method(GET).with_uri("${base}/videos/film.mp4").with_headers([{ name: "Range", value: "bytes=5-9" }]), {}).map_err(|err| Failed("the range request: ${Str.inspect(err)}"))?
	check(Response.status(part) == 206 and body_of(part) == "bytes", "a mount did not answer a range request: ${Response.status(part).to_str()} ${body_of(part)}")?

	download = get!("${base}/download/videos/film.mp4")?
	check(body_of(download) == "film bytes", "JOY_MOUNT_DOWNLOAD did not serve its file: ${body_of(download)}")?
	check(header_of(download, "content-disposition") == "attachment; filename*=UTF-8''film.mp4", "a download is named ${header_of(download, "content-disposition")}")?

	# A mount answers for its whole path, and only for what is below it.
	missing = get!("${base}/videos/none.mp4")?
	check(Response.status(missing) == 404, "a missing file got ${Response.status(missing).to_str()}: ${body_of(missing)}")?
	for escape in ["${base}/videos/..%2Fsecret.txt", "${base}/videos/%2e%2e/secret.txt"] {
		escaped = get!(escape)?
		check(Response.status(escaped) == 404 and body_of(escaped) != "not served", "${escape} left the folder: ${body_of(escaped)}")?
	}
	beside = get!("${base}/videosx/film.mp4")?
	contains(body_of(beside), "pages GET /videosx/film.mp4")?

	# A folder that was missing is created, and serves what arrives in it.
	write!(ctx, "not/there/yet/new.txt", "arrived")?
	later = get!("${base}/later/new.txt")?
	check(body_of(later) == "arrived", "a created folder did not serve its file: ${body_of(later)}")?

	_ = stop_dev!(dev1)?
	Server.stop!(pages)
	Ok({})
}

## Clicking through slow pages leaves requests the browser has given up on, which
## still hold their handlers until the backend answers. More of them than the dev
## server has handlers, and files still have to get past them at once.
dev_abandoned_pages! : Ctx => Try({}, [Failed(Str)])
dev_abandoned_pages! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "media/a.txt", "a file")?
	write!(ctx, "public/robots.txt", "User-agent: *")?
	slow =
		Server.start!(
			{ port: 0, handlers: 64 },
			|_request| {
				_ = Sleep.millis!(3_000)
				Ok(Server.respond(Response.from_status(200)))
			},
		)
			.map_err(|err| Failed("the backend did not start: ${Str.inspect(err)}"))?
	dev = start_dev!(ctx, ["--port", "0", "--proxy", "/slow=http://127.0.0.1:${slow.port().to_str()}", "--mount", "/files=media"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	abandon = "i=0; while [ $i -lt 40 ]; do i=$((i + 1)); curl -s -o /dev/null -m 0.2 http://localhost:${port}/slow/$i & done; wait"
	_ = Cmd.new(OsStr.from_str("sh")).args(["-c", abandon].map(OsStr.from_str)).run!() ? |err| Failed("abandoning the pages: ${Str.inspect(err)}")
	started = Monotonic.now!()
	file = get!("http://localhost:${port}/files/a.txt")?
	public = get!("http://localhost:${port}/robots.txt")?
	wasm = get!("http://localhost:${port}/app/app.wasm")?
	took = Monotonic.since(Monotonic.now!(), started).to_millis()
	check(body_of(file) == "a file", "the mount's file did not arrive: ${body_of(file)}")?
	check(body_of(public) == "User-agent: *", "public/'s file did not arrive: ${body_of(public)}")?
	check(header_of(wasm, "content-type") == "application/wasm", "the dev build did not arrive")?
	check(took < 1_500, "files waited ${took.to_str()} ms behind pages the browser gave up on")?
	_ = stop_dev!(dev1)?
	Server.stop!(slow)
	Ok({})
}

## A browser opens 6 connections to a port, and every open page holds one for its
## events, so the events keep off the port of the pages.
dev_events_port! : Ctx => Try({}, [Failed(Str)])
dev_events_port! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	runtime = read!(ctx, ".joy/dev/client/runtime.js")?
	events_port =
		match runtime.split_first("const JOY_DEV_PORT = ") {
			Ok({ after, .. }) => (after.split_on(";").first() ?? "").trim()
			Err(_) => return Err(Failed("the runtime names no events port"))
		}
	check(events_port != port, "pages and events share the port ${port}")?
	check(read!(ctx, ".joy/events-port")?.trim() == events_port, "the events port is not remembered")?
	_ = expect_event!(listen!(events_port)?, "hello", 1)?
	wasm = get!("http://localhost:${events_port}/app/app.wasm")?
	check(Response.status(wasm) == 404, "the events port serves files: ${Response.status(wasm).to_str()}")?
	page_wasm = get!("http://localhost:${port}/app/app.wasm")?
	check(Response.status(page_wasm) == 200, "the port of the pages lost its files: ${Response.status(page_wasm).to_str()}")?
	_ = stop_dev!(dev1)?
	Ok({})
}

dev_bad_mount! : Ctx => Try({}, [Failed(Str)])
dev_bad_mount! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	out = joy_ok!(ctx, ["dev", "--mount", "videos=media"], 1)?
	contains(out, "--mount takes PATH=DIR")?
	download = joy_ok!(ctx, ["dev", "--mount-download", "/videos"], 1)?
	contains(download, "--mount-download takes PATH=DIR")
}

# The generated/ package

## A server on joy-cli-platform that names generated/, reads assets.json
## through `Names`, and prints what it found. With `stay`, it keeps running.
names_server_source : Bool -> Str
names_server_source = |stay| {
	Str.join_with(
		[
			"app [main!] {",
			"\tpf: platform \"${cli_platform}\",",
			"\tgen: \"../generated/main.roc\",",
			"}",
			"",
			"import pf.Env",
			"import pf.OsStr",
			"import pf.Path",
			"import pf.Sleep",
			"import pf.Stdout",
			"import gen.Asset",
			"import gen.Names",
			"",
			"main! : List(OsStr) => Try({}, _)",
			"main! = |_args| {",
			"\tfile = Env.var_str!(OsStr.from_str(\"JOY_ASSETS_JSON\")) ?? \"dist/assets.json\"",
			"\tfolder =",
			"\t\tmatch file.split_last(\"/\") {",
			"\t\t\tOk({ before, .. }) => before",
			"\t\t\tErr(_) => \".\"",
			"\t\t}",
			"\ttext = Path.utf8(file).read_utf8!()?",
			"\tnames =",
			"\t\tmatch Names.parse(text, folder) {",
			"\t\t\tOk(found) => found",
			"\t\t\tErr(problem) => {",
			"\t\t\t\tStdout.line!(\"refused: \${Str.inspect(problem)}\")?",
			"\t\t\t\treturn Err(Exit(3))",
			"\t\t\t}",
			"\t\t}",
			"\tStdout.line!(\"css \${Asset.path(\"css/site.css\")}\")?",
			"\tStdout.line!(\"joy \${Names.joy(names)}\")?",
			"\tStdout.line!(\"wasm \${Names.wasm(names, App)}\")?",
			"\tStdout.line!(\"url \${Asset.url(\"css/site.css\")}\")?",
			"\tfiles = Names.joy_files(names)",
			"\tStdout.line!(\"loader \${files.loader} app \${(files.wasm)(\"app\")}\")?",
			if (stay) "\t_ = Sleep.millis!(1_000_000_000)" else "",
			"\tOk({})",
			"}",
		],
		"\n",
	)
}

## A bundle that names generated/ and links an asset by its quoted name.
asset_bundle_source : Ctx, Str, Str -> Str
asset_bundle_source = |ctx, file, asset|
	app_source(platform_from(ctx, file), "Asset.path(\"${asset}\")", "import gen.Asset", "")
		.replace_first("\thtml: ", "\tgen: \"../generated/main.roc\",\n\thtml: ")

generated_only_when_named! : Ctx => Try({}, [Failed(Str)])
generated_only_when_named! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "assets/css/site.css", "body {}")?
	_ = joy_ok!(ctx, ["build"], 0)?
	check(!exists!(ctx, "generated"), "generated/ was written though no header names it")?
	write!(ctx, "server/main.roc", names_server_source(False))?
	bundle!(ctx, "client/Checkout/cart.roc", "cart")?
	write!(ctx, "public/robots.txt", "User-agent: *")?
	_ = joy_ok!(ctx, ["build", "--server-opt", "dev"], 0)?
	for file in ["main.roc", "Bundle.roc", "Asset.roc", "Public.roc", "Names.roc"] {
		check(exists!(ctx, "generated/${file}"), "generated/${file} is missing")?
	}
	bundle_roc = read!(ctx, "generated/Bundle.roc")?
	contains(bundle_roc, "Bundle := [CheckoutCart, App].{")?
	contains(bundle_roc, "CheckoutCart => \"Checkout/cart\"")?
	asset_roc = read!(ctx, "generated/Asset.roc")?
	contains(asset_roc, "(\"css/site.css\", \"css/site.css\"),")?
	public_roc = read!(ctx, "generated/Public.roc")?
	contains(public_roc, "\"robots.txt\",")?
	# The listings are in byte order, so the checked-in package is the same
	# on every machine whatever order the file system lists them in.
	names = ["Z.txt", "a.txt", "b.txt", "b/c.txt", "m.txt", "q.txt", "q/r/s.txt", "x.txt", "y.txt", "z.txt"]
	for name in names {
		write!(ctx, "public/sorted/${name}", name)?
	}
	_ = joy_ok!(ctx, ["build", "--server-opt", "dev"], 0)?
	listed = read!(ctx, "generated/Public.roc")?.split_on("\n").keep_if(|line| line.contains("\"sorted/")).map(|line| line.trim())
	check(listed == names.map(|name| "\"sorted/${name}\","), "public/ is not listed in byte order: ${Str.inspect(listed)}")?
	formatted =
		Cmd.new(OsStr.from_str("roc"))
			.args(["fmt", "--check"].concat(["main.roc", "Bundle.roc", "Asset.roc", "Public.roc", "Names.roc"].map(|file| "generated/${file}")).map(OsStr.from_str))
			.cwd(Path.utf8(ctx.dir))
			.run!()
			? |err| Failed("roc fmt did not run: ${Str.inspect(err)}")
	check(formatted.status == Exited(0), "generated/ is not formatted:\n${Str.from_utf8_lossy(formatted.stdout_bytes)}${Str.from_utf8_lossy(formatted.stderr_bytes)}")
}

generated_build! : Ctx => Try({}, [Failed(Str)])
generated_build! = |ctx| {
	write!(ctx, "client/app.roc", asset_bundle_source(ctx, "client/app.roc", "css/site.css"))?
	write!(ctx, "assets/css/site.css", "body { color: teal }")?
	write!(ctx, "server/main.roc", names_server_source(False))?
	_ = joy_ok!(ctx, ["build", "--server-opt", "dev", "--client-url", "/static"], 0)?
	json = read!(ctx, "dist/assets.json")?
	css = files_in!(ctx, "dist/client/css").first() ?? "?"
	wasm = wasm_name!(ctx, "app")?
	contains(json, "\"css/site.css\": \"css/${css}\"")?
	# The repository keeps plain names, and the build's copy the hashed ones.
	contains(read!(ctx, "generated/Asset.roc")?, "(\"css/site.css\", \"css/site.css\"),")?
	contains(read!(ctx, "dist/generated/Asset.roc")?, "(\"css/site.css\", \"css/${css}\"),")?
	ran =
		Cmd.new(OsStr.from_str("${ctx.dir}/dist/server/main"))
			.env(OsStr.from_str("JOY_ASSETS_JSON"), OsStr.from_str("${ctx.dir}/dist/assets.json"))
			.cwd(Path.utf8(ctx.dir))
			.run!()
			? |err| Failed("the server did not run: ${Str.inspect(err)}")
	out = Str.from_utf8_lossy(ran.stdout_bytes)
	contains(out, "css css/${css}")?
	contains(out, "url /static/css/${css}")?
	contains(out, "loader /static/joy.")?
	contains(out, "app /static/${wasm}")?
	contains(read!(ctx, "generated/Names.roc")?, "client_url = \"/static/\"")?
	contains(out, "wasm ${wasm}")?
	contains(out, "joy joy.")
}

generated_refuses! : Ctx => Try({}, [Failed(Str)])
generated_refuses! = |ctx| {
	write!(ctx, "client/app.roc", asset_bundle_source(ctx, "client/app.roc", "css/site.css"))?
	write!(ctx, "assets/css/site.css", "body {}")?
	write!(ctx, "server/main.roc", names_server_source(False))?
	_ = joy_ok!(ctx, ["build", "--server-opt", "dev"], 0)?
	# A server compiled with the build's hashed names, given plain ones.
	write!(ctx, "plain.json", "{ \"roots\": {}, \"joy\": \"joy.js\", \"bundles\": { \"app\": \"app/app.wasm\" }, \"assets\": { \"css/site.css\": \"css/site.css\" }, \"public\": [] }")?
	ran =
		Cmd.new(OsStr.from_str("${ctx.dir}/dist/server/main"))
			.env(OsStr.from_str("JOY_ASSETS_JSON"), OsStr.from_str("${ctx.dir}/plain.json"))
			.cwd(Path.utf8(ctx.dir))
			.run!()
			? |err| Failed("the server did not run: ${Str.inspect(err)}")
	contains(Str.from_utf8_lossy(ran.stdout_bytes), "refused: AssetsDiffer(\"css/site.css\")")?
	write!(ctx, "nobundle.json", "{ \"roots\": {}, \"joy\": \"joy.js\", \"bundles\": {}, \"assets\": {}, \"public\": [] }")?
	missing =
		Cmd.new(OsStr.from_str("${ctx.dir}/dist/server/main"))
			.env(OsStr.from_str("JOY_ASSETS_JSON"), OsStr.from_str("${ctx.dir}/nobundle.json"))
			.cwd(Path.utf8(ctx.dir))
			.run!()
			? |err| Failed("the server did not run: ${Str.inspect(err)}")
	contains(Str.from_utf8_lossy(missing.stdout_bytes), "refused: NoWasm(\"app\")")
}

generated_missing_asset! : Ctx => Try({}, [Failed(Str)])
generated_missing_asset! = |ctx| {
	write!(ctx, "client/app.roc", asset_bundle_source(ctx, "client/app.roc", "css/missing.css"))?
	write!(ctx, "assets/css/site.css", "body {}")?
	out = joy_ok!(ctx, ["build"], 1)?
	contains(out, "There is no file assets/css/missing.css.")
}

generated_same_tag! : Ctx => Try({}, [Failed(Str)])
generated_same_tag! = |ctx| {
	write!(ctx, "client/a_b.roc", asset_bundle_source(ctx, "client/a_b.roc", "x.css"))?
	bundle!(ctx, "client/A/b.roc", "other")?
	write!(ctx, "assets/x.css", "x")?
	out = joy_ok!(ctx, ["build"], 1)?
	contains(out, "would both be AB in generated/Bundle.roc")
}

generated_not_a_tag! : Ctx => Try({}, [Failed(Str)])
generated_not_a_tag! = |ctx| {
	write!(ctx, "client/app.roc", asset_bundle_source(ctx, "client/app.roc", "x.css"))?
	bundle!(ctx, "client/2fa.roc", "second factor")?
	write!(ctx, "assets/x.css", "x")?
	out = joy_ok!(ctx, ["build"], 1)?
	contains(out, "client/2fa.roc would be 2fa in generated/Bundle.roc, and a tag is a capital letter followed by letters and digits. Rename the file.")?
	check(!(read!(ctx, "generated/Bundle.roc") ?? "").contains("2fa"), "a broken generated/Bundle.roc was written")
}

generated_dev! : Ctx => Try({}, [Failed(Str)])
generated_dev! = |ctx| {
	write!(ctx, "client/app.roc", asset_bundle_source(ctx, "client/app.roc", "css/site.css"))?
	write!(ctx, "assets/css/site.css", "body {}")?
	write!(ctx, "server/main.roc", names_server_source(True))?
	dev = start_dev!(ctx, [], [])?
	dev1 = wait_for!(dev, "[server] wasm app/app.wasm", 1)?
	contains(dev1.out, "[server] css css/site.css")?
	assets = read!(ctx, ".joy/dev/assets.json")?
	contains(assets, "\"assets\": { \"css/site.css\": \"css/site.css\" }")?
	write!(ctx, "assets/js/new.js", "// new")?
	dev2 = wait_for!(dev1, "Wrote generated/", 2)?
	contains(read!(ctx, "generated/Asset.roc")?, "(\"js/new.js\", \"js/new.js\"),")?
	contains(read!(ctx, ".joy/dev/assets.json")?, "\"js/new.js\": \"js/new.js\"")?
	# The server and the bundle read generated/, so both build again.
	dev3 = wait_for!(wait_for!(dev2, "built server", 2)?, "built app", 2)?
	_ = stop_dev!(dev3)?
	Ok({})
}

dev_watch! : Ctx => Try({}, [Failed(Str)])
dev_watch! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	# A watcher that goes on in a child of its shell, which has to stop too.
	dev = start_dev!(ctx, ["--watch", "echo started $$; sleep 987; echo never", "--watch", "printf 'one\\ntwo\\n'; exit 3"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	dev2 = wait_for!(dev1, "[echo] started", 1)?
	dev3 = wait_for!(dev2, "[printf] two", 1)?
	dev4 = wait_for!(dev3, "printf exited: Exited(3). ./joy does not start it again.", 1)?
	check(dev4.out.split_on("printf exited").len() == 2, "a finished watcher was reported more than once")?
	_ = stop_dev!(dev4)?
	left = Cmd.new(OsStr.from_str("pgrep")).args(["-f", "sleep 987"].map(OsStr.from_str)).run!() ? |err| Failed("pgrep: ${Str.inspect(err)}")
	check(left.status == Exited(1), "a --watch command outlived ./joy dev:\n${Str.from_utf8_lossy(left.stdout_bytes)}")
}

dev_watch_first_start! : Ctx => Try({}, [Failed(Str)])
dev_watch_first_start! = |ctx| {
	write!(ctx, "client/app.roc", asset_bundle_source(ctx, "client/app.roc", "made.css"))?
	write!(ctx, "assets/other.css", "body {}")?
	# Later than the first build, as a compiler that takes a moment would be.
	dev = start_dev!(ctx, ["--watch", "sleep 3; printf 'p {}' > assets/made.css; sleep 987"], [])?
	dev1 = wait_for!(dev, "app failed", 1)?
	dev2 = wait_for!(dev1, "built app", 1)?
	_ = stop_dev!(dev2)?
	Ok({})
}

build_before! : Ctx => Try({}, [Failed(Str)])
build_before! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	out = joy_ok!(ctx, ["build", "--before", "mkdir -p assets && printf 'p {}' > assets/one.css", "--before", "printf 'a {}' > assets/two.css"], 0)?
	contains(out, "Running mkdir -p assets")?
	names = files_in!(ctx, "dist/client")
	check(names.any(|name| name.starts_with("one.") and name.ends_with(".css")), "the first command's file was not built: ${Str.inspect(names)}")?
	check(names.any(|name| name.starts_with("two.") and name.ends_with(".css")), "the second command's file was not built: ${Str.inspect(names)}")?
	failed = run_joy!(ctx, ["build", "--before", "exit 3", "--before", "printf 'x' > assets/after.css"])?
	check(failed.code != 0, "a failed --before did not fail the build")?
	contains(failed.out, "--before failed, so nothing was built: exit 3")?
	check(!exists!(ctx, "assets/after.css"), "the command after a failed one ran")?
	kept = files_in!(ctx, "dist/client")
	check(kept.any(|name| name.starts_with("one.")), "a failed --before emptied the last build")
}

dev_behind_proxy! : Ctx => Try({}, [Failed(Str)])
dev_behind_proxy! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "public/robots.txt", "User-agent: *")?
	write!(ctx, "server/main.roc", server_source("from the server"))?
	api = echo_backend!("api")?
	# No $PORT, so ./joy picks one and starts the server with it.
	dev = start_dev!(
		ctx,
		["--port", "0"],
		[
			("JOY_SERVE_FILES", "1"),
			("JOY_CLIENT_URL", "/static"),
			("JOY_PROXY", "/api=http://127.0.0.1:${api.port().to_str()}"),
		],
	)?
	dev1 = wait_for!(dev, "app listening on", 1)?
	server_port = port_after(dev1.out, "app listening on")?
	contains(dev1.out, "the files under /static/ from the builds, and everything else from the server on ${server_port}")?
	port = port_after(dev1.out, "Starting on http://localhost")?
	page = get!("http://localhost:${port}/books")?
	check(body_of(page) == "from the server", "a page did not come from the project's server: ${body_of(page)}")?
	wasm = get!("http://localhost:${port}/static/app/app.wasm")?
	check(header_of(wasm, "content-type") == "application/wasm", "the dev build is not served under JOY_CLIENT_URL")?
	robots = get!("http://localhost:${port}/static/robots.txt")?
	check(body_of(robots) == "User-agent: *", "public/ is not served under JOY_CLIENT_URL")?
	answered = get!("http://localhost:${port}/api/books")?
	contains(body_of(answered), "api GET /api/books")?
	_ = stop_dev!(dev1)?
	Server.stop!(api)
	Ok({})
}

dev_server_without_files! : Ctx => Try({}, [Failed(Str)])
dev_server_without_files! = |ctx| {
	bundle!(ctx, "client/app.roc", "app")?
	write!(ctx, "server/main.roc", server_answering(404, "no such page"))?
	# A port that was free a moment ago, for the project's server.
	probe = echo_backend!("probe")?
	port = probe.port().to_str()
	Server.stop!(probe)
	dev = start_dev!(ctx, [], [("PORT", port)])?
	warned = wait_for!(dev, "answers 404 for /joy.js", 1)?
	contains(warned.out, "The server on ${port} answers 404 for /joy.js, so its pages load without their bundles.")?
	contains(warned.out, "set JOY_SERVE_FILES=1")?
	ready = wait_for!(warned, "Ready on http://localhost:${port}/", 1)?
	_ = stop_dev!(ready)?
	Ok({})
}

# ./joy init

init_template! : Ctx => Try({}, [Failed(Str)])
init_template! = |ctx| {
	out = joy_ok!(ctx, ["init", "my-app", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 0)?
	contains(out, "Started a project in my-app from the spa-pages template")?
	contains(out, "    cd my-app\n    ./joy dev")?
	for file in ["client/app.roc", "client/Route.roc", "client/Page/Home.roc", "public/index.html", "assets/css/style.css", "README.md"] {
		check(exists!(ctx, "my-app/${file}"), "init did not write ${file}")?
	}
	ignored = read!(ctx, "my-app/.gitignore")?
	check(ignored == "/joy\n/.joy/\n/dist/\n", "unexpected .gitignore:\n${ignored}")?
	bundle_file = read!(ctx, "my-app/client/app.roc")?
	# The bundle names this checkout's platform from where the project is.
	lacks(bundle_file, "\"../../../../platform/main.roc\"")?
	# The README says how a fresh clone installs ./joy.
	readme = read!(ctx, "my-app/README.md")?
	contains(readme, "    roc run ../")?
	contains(readme, "/cli/main.roc init\n")?
	lacks(readme, "<INSERT JOY INSTALL COMMAND HERE>")?
	installed = Path.utf8("${ctx.dir}/my-app/joy")
	check(installed.is_executable!() ?? False, "init did not install an executable ./joy")?
	# The project's own ./joy builds it.
	project = { ..ctx, dir: "${ctx.dir}/my-app", joy: "${ctx.dir}/my-app/joy" }
	built = joy_ok!(project, ["build"], 0)?
	contains(built, "Built 1 bundle")?
	# The page names joy.js from the site's root, and so its wasm, since a
	# host answers this page for every URL of the app.
	page = read!(project, "dist/client/index.html")?
	contains(page, "data-joy-wasm=\"/app/app.")?
	lacks(page, "src=\"/joy.js\"")
}

## init_template! goes through spa-pages. The other two only have to start a
## project that its own ./joy builds.
init_other_templates! : Ctx => Try({}, [Failed(Str)])
init_other_templates! = |ctx| {
	for name in ["spa-minimal", "spa-pages-expanded"] {
		out = joy_ok!(ctx, ["init", name, "--template", name, "--joy-checkout", ctx.joy_root], 0)?
		contains(out, "Started a project in ${name} from the ${name} template")?
		bundle_file = read!(ctx, "${name}/client/app.roc")?
		lacks(bundle_file, "\"../../../../platform/main.roc\"")?
		lacks(read!(ctx, "${name}/README.md")?, "<INSERT JOY INSTALL COMMAND HERE>")?
		project = { ..ctx, dir: "${ctx.dir}/${name}", joy: "${ctx.dir}/${name}/joy" }
		built = joy_ok!(project, ["build"], 0)?
		contains(built, "Built 1 bundle")?
	}
	Ok({})
}

init_folder_rules! : Ctx => Try({}, [Failed(Str)])
init_folder_rules! = |ctx| {
	write!(ctx, "busy/notes.txt", "mine")?
	refused = joy_ok!(ctx, ["init", "busy", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 1)?
	contains(refused, "busy has files in it already:\n  notes.txt\nStart in an empty directory, name a new one (init my-app), or start here anyway with --non-empty.")?
	check(!exists!(ctx, "busy/client"), "init wrote into a folder with files")?
	# More than five files are not listed.
	for name in ["a", "b", "c", "d", "e", "f"] {
		write!(ctx, "crowded/${name}.txt", name)?
	}
	crowded = joy_ok!(ctx, ["init", "crowded", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 1)?
	contains(crowded, "crowded has files in it already.\n")?
	lacks(crowded, "a.txt")?
	# --non-empty starts beside them, and never writes over a file.
	_ = joy_ok!(ctx, ["init", "busy", "--non-empty", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 0)?
	check(exists!(ctx, "busy/client/app.roc"), "init --non-empty did not start the project")?
	kept = read!(ctx, "busy/notes.txt")?
	check(kept == "mine", "init changed notes.txt")?
	write!(ctx, "readme/README.md", "my own")?
	clash = joy_ok!(ctx, ["init", "readme", "--non-empty", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 1)?
	contains(clash, "readme has its own README.md, which the spa-pages template would write over.")?
	readme = read!(ctx, "readme/README.md")?
	check(readme == "my own", "init wrote over README.md")?
	check(!exists!(ctx, "readme/client"), "init wrote part of a template beside a clash")?
	# A Roc download beside the project does not count.
	write!(ctx, "with-roc/roc_nightly-linux_x86_64-2026-11-03-34bd006/roc", "roc")?
	write!(ctx, "with-roc/roc_nightly-linux_x86_64-2026-11-03-34bd006.tar.gz", "roc")?
	_ = joy_ok!(ctx, ["init", "with-roc", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 0)?
	check(exists!(ctx, "with-roc/client/app.roc"), "init refused a folder with only Roc in it")?
	# Dot files do not count, and .gitignore keeps what it had.
	write!(ctx, "dotted/.git/HEAD", "ref: refs/heads/main\n")?
	write!(ctx, "dotted/.gitignore", "node_modules/\n/dist/")?
	_ = joy_ok!(ctx, ["init", "dotted", "--template", "spa-pages", "--joy-checkout", ctx.joy_root], 0)?
	ignored = read!(ctx, "dotted/.gitignore")?
	check(ignored == "node_modules/\n/dist/\n/joy\n/.joy/\n", "unexpected .gitignore:\n${ignored}")?
	unknown = joy_ok!(ctx, ["init", "other", "--template", "nope", "--joy-checkout", ctx.joy_root], 1)?
	contains(unknown, "There is no template called nope. The templates are spa-minimal, spa-pages, spa-pages-expanded.")?
	check(!exists!(ctx, "other"), "init made a folder for a template it does not have")
}

init_existing_app! : Ctx => Try({}, [Failed(Str)])
init_existing_app! = |ctx| {
	bundle!(ctx, "client/app.roc", "mine")?
	# Installing ./joy beside an app needs no checkout.
	out = joy_with!(ctx, ["init", "--template", "spa-pages"], 0, [("JOY_CHECKOUT", "")])?
	contains(out, "This directory has a Joy app already, so init only installed ./joy.")?
	mine = read!(ctx, "client/app.roc")?
	contains(mine, "\"mine\"")?
	check(exists!(ctx, "joy"), "init did not install ./joy")?
	check(!exists!(ctx, "client/Route.roc"), "init wrote a template over an app")
}

init_no_input! : Ctx => Try({}, [Failed(Str)])
init_no_input! = |ctx| {
	asked = joy_ok!(ctx, ["init", "my-app", "--no-input", "--joy-checkout", ctx.joy_root], 1)?
	contains(asked, "Which template? Name one with --template:\n  spa-minimal         A single file with a counter example.\n  spa-pages           Routing")?
	contains(asked, "Want to see the templates? https://github.com/niclas-ahden/joy/tree/main/examples/templates")?
	check(!exists!(ctx, "my-app"), "init made a folder before a template was chosen")?
	no_checkout = joy_with!(ctx, ["init", "my-app", "--template", "spa-pages"], 1, [("JOY_CHECKOUT", "")])?
	contains(no_checkout, "init needs a Joy checkout: --joy-checkout <dir>, or JOY_CHECKOUT.")?
	not_joy = joy_ok!(ctx, ["init", "my-app", "--template", "spa-pages", "--joy-checkout", ctx.dir], 1)?
	contains(not_joy, "is not a Joy checkout")?
	from_env = joy_with!(ctx, ["init", "my-app", "--template", "spa-pages"], 0, [("JOY_CHECKOUT", ctx.joy_root)])?
	contains(from_env, "Started a project in my-app from the spa-pages template")
}

## `roc run <cli> init` is the first command of a project. roc interprets the
## CLI then, so there is no program to copy, and init builds one.
init_interpreted! : Ctx => Try({}, [Failed(Str)])
init_interpreted! = |ctx| {
	ran =
		Cmd.new(OsStr.from_str("roc"))
			.args(["run", "${ctx.joy_root}/cli/main.roc", "init", "my-app", "--template", "spa-pages", "--joy-checkout", ctx.joy_root].map(OsStr.from_str))
			.cwd(Path.utf8(ctx.dir))
			.stdin(Null)
			.stderr(MergeWithStdout)
			.timeout(Duration.minutes(5))
			.run!()
			? |err| Failed("roc run cli/main.roc init did not run: ${Str.inspect(err)}")
	out = Str.from_utf8_lossy(ran.stdout_bytes)
	contains(out, "Started a project in my-app from the spa-pages template")?
	check((Path.utf8("${ctx.dir}/my-app/joy").is_executable!() ?? False), "init did not install an executable ./joy:\n${out}")?
	check(!exists!(ctx, "my-app/.joy.new"), "init left .joy.new behind")?
	# The program init built runs on its own, from the project.
	project = { ..ctx, dir: "${ctx.dir}/my-app", joy: "${ctx.dir}/my-app/joy" }
	listed = joy_ok!(project, ["bundles"], 0)?
	contains(listed, "app  App  client/app.roc")?
	built = joy_ok!(project, ["build"], 0)?
	contains(built, "Built 1 bundle")
}

## A package can bring a browser feature: Roc functions on Effect.call, and
## their JavaScript beside them, Greeter.js for Greeter.roc. A build keeps the
## effects an app calls, as it does with Joy's own.
build_package_feature! : Ctx => Try({}, [Failed(Str)])
build_package_feature! = |ctx| {
	write!(ctx, "greeter/main.roc", "package [Greeter] { pf: platform \"${platform_from(ctx, "greeter/main.roc")}\" }\n")?
	write!(
		ctx,
		"greeter/Greeter.roc",
		Str.join_with(
			[
				"import pf.Effect",
				"import pf.Wire",
				"",
				"Greeter := [].{",
				"\tgreet : Str -> Effect(msg)",
				"\tgreet = |name| Effect.send(\"greeter/say_hello\", Wire.writer({}).str(name).done())",
				"",
				"\twave : Str -> Effect(msg)",
				"\twave = |name| Effect.send(\"greeter/wave_goodbye\", Wire.writer({}).str(name).done())",
				"}",
			],
			"\n",
		),
	)?
	write!(ctx, "greeter/Greeter.js", "//// effect greeter/say_hello\ndefineEffect('greeter/say_hello', (args) => console.log('hello ' + args.str()));\n\n//// effect greeter/wave_goodbye\ndefineEffect('greeter/wave_goodbye', (args) => console.log('goodbye ' + args.str()));\n")?
	source =
		app_source(platform_from(ctx, "client/app.roc"), "\"greets\"", "import greeter.Greeter", "")
			.replace_first("\thtml: ", "\tgreeter: \"../greeter/main.roc\",\n\thtml: ")
			.replace_first("init = |_| ({}, [])", "init = |_| ({}, [Greeter.greet(\"you\")])")
	write!(ctx, "client/app.roc", source)?
	_ = joy_ok!(ctx, ["build"], 0)?
	runtime = read!(ctx, "dist/client/effects.js")?
	contains(runtime, "greeter/say_hello")?
	lacks(runtime, "greeter/wave_goodbye")?
	# ./joy dev serves every feature, as the wasm changes on each edit.
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "built app", 1)?
	served = read!(ctx, ".joy/dev/client/effects.js")?
	_ = stop_dev!(dev1)?
	contains(served, "greeter/say_hello")?
	contains(served, "greeter/wave_goodbye")
}

## A package called greeter, whose `greet` is `greet_body` and whose Greeter.js
## defines greeter/say_hello and greeter/wave_goodbye, and an app that
## starts with `first_effect`.
greeter! : Ctx, Str, Str => Try({}, [Failed(Str)])
greeter! = |ctx, greet_body, first_effect| {
	write!(ctx, "greeter/main.roc", "package [Greeter] { pf: platform \"${platform_from(ctx, "greeter/main.roc")}\" }\n")?
	write!(
		ctx,
		"greeter/Greeter.roc",
		Str.join_with(
			[
				"import pf.Effect",
				"import pf.Wire",
				"",
				"Greeter := [].{",
				"\tgreet : Str -> Effect(msg)",
				"\tgreet = |name| ${greet_body}",
				"",
				"\twave : Str -> Effect(msg)",
				"\twave = |name| Effect.send(\"greeter/wave_goodbye\", Wire.writer({}).str(name).done())",
				"}",
				"",
				"hello_id = \"greeter/say_hello\"",
			],
			"\n",
		),
	)?
	write!(ctx, "greeter/Greeter.js", "//// effect greeter/say_hello\ndefineEffect('greeter/say_hello', (args) => console.log('hello ' + args.str()));\n\n//// effect greeter/wave_goodbye\ndefineEffect('greeter/wave_goodbye', (args) => console.log('goodbye ' + args.str()));\n")?
	source =
		app_source(platform_from(ctx, "client/app.roc"), "\"greets\"", "import greeter.Greeter", "")
			.replace_first("\thtml: ", "\tgreeter: \"../greeter/main.roc\",\n\thtml: ")
			.replace_first("init = |_| ({}, [])", "init = |_| ({}, [${first_effect}])")
	write!(ctx, "client/app.roc", source)
}

## roc cannot know that a call has no JavaScript behind it: a misspelt id, or
## a module without its JavaScript file. ./joy reads the ids an app uses out
## of its wasm and fails the build when nothing defines one, in the words of
## where it is written and what the right ids are. An id is a string someone
## wrote, which roc sees to, so the wasm has every one.
missing_effect! : Ctx => Try({}, [Failed(Str)])
missing_effect! = |ctx| {
	misspelt = "Effect.send(\"greeter/say_hallo\", Wire.writer({}).str(name).done())"
	greeter!(ctx, misspelt, "Greeter.greet(\"you\")")?
	refused = joy_ok!(ctx, ["build"], 1)?
	contains(refused, "── ✗ custom effect without javascript ───────────────── greeter/Greeter.roc:6:30\n\nNo JavaScript defines the custom effect with this id:\n\n    greet = |name| Effect.send(\"greeter/say_hallo\", Wire.writer({}).str(name).done())\n                                ^^^^^^^^^^^^^^^^^\n\nDid you mean this one?\n\n    greeter/say_hello\n\nIf the id is the one you meant, then its JavaScript is what is missing:\na section that starts with `//// effect greeter/say_hallo`\nin greeter/Greeter.js.")?
	contains(refused, "The guide has more on this: https://niclas-ahden.github.io/joy/#custom-effects")?
	contains(refused, "The custom effects do not check out, so dist/ is incomplete.")?
	check(!exists!(ctx, "dist/client/runtime.js"), "a build with a custom effect missing wrote a runtime.js")?

	# The same under ./joy dev, as a build that failed, until it is put right.
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "app failed", 1)?
	contains(dev1.out, "greeter/Greeter.roc:6:30\n\nNo JavaScript defines the custom effect with this id:")?
	port = port_after(dev1.out, "Starting on http://localhost")?
	events = expect_event!(listen!(port)?, "failed", 1)?
	contains(events.seen, "data: Did you mean this one?\ndata: \ndata:     greeter/say_hello\n")?
	greeter!(ctx, "Effect.send(\"greeter/say_hello\", Wire.writer({}).str(name).done())", "Greeter.greet(\"you\")")?
	dev2 = wait_for!(dev1, "built app", 1)?
	_ = expect_event!(events, "fixed", 1)?
	_ = stop_dev!(dev2)?

	# A misspelt id the app never reaches is the package's own trouble.
	greeter!(ctx, misspelt, "Greeter.wave(\"you\")")?
	_ = joy_ok!(ctx, ["build"], 0)?

	# A module without its JavaScript file has no custom effect at all.
	greeter!(ctx, "Effect.send(\"greeter/say_hello\", Wire.writer({}).str(name).done())", "Greeter.greet(\"you\")")?
	_ = Path.utf8("${ctx.dir}/greeter/Greeter.js").delete!()
	without = joy_ok!(ctx, ["build"], 1)?
	contains(without, "No effect has an id that starts with greeter/ yet, so the JavaScript\nof this one is still to be written. It goes in a new file beside the module,\ngreeter/Greeter.js, and starts like this:\n\n    //// effect greeter/say_hello\n    defineEffect('greeter/say_hello', (args) => {\n")?

	# An id can be a named value, as it is still a string someone wrote.
	greeter!(ctx, "Effect.send(hello_id, Wire.writer({}).str(name).done())", "Greeter.greet(\"you\")")?
	_ = joy_ok!(ctx, ["build"], 0)?
	contains(read!(ctx, "dist/client/effects.js")?, "greeter/say_hello")?

	# One put together while the app runs is not, and roc refuses it.
	greeter!(ctx, "Effect.send(Str.concat(\"greeter/\", name), [])", "Greeter.greet(\"you\")")?
	made = joy_ok!(ctx, ["build"], 1)?
	contains(made, "Effect.send(Str.concat(\"greeter/\", name), [])")?
	contains(made, "Hint from ./joy: Effect.Id and Sub.Id are the ids of effects.")?

	# roc says a module is private when the package's list lacks it, and
	# ./joy says which list.
	greeter!(ctx, "Effect.send(\"greeter/say_hello\", Wire.writer({}).str(name).done())", "Greeter.greet(\"you\")")?
	write!(ctx, "greeter/main.roc", read!(ctx, "greeter/main.roc")?.replace_first("package [Greeter]", "package []"))?
	unlisted = joy_ok!(ctx, ["build"], 1)?
	contains(unlisted, "Hint from ./joy: Greeter is not in the list of the modules of the package greeter.\nAdd it to the list at the top of client/../greeter/main.roc:\n\n    package [..., Greeter] {")
}

## A custom effect a project defines for itself: the call in one of its own
## modules, and its JavaScript in the file of that module's name beside it.
## ./joy dev watches that file, and a save has the pages start over on it.
project_feature! : Ctx => Try({}, [Failed(Str)])
project_feature! = |ctx| {
	source =
		app_source(platform_from(ctx, "client/app.roc"), "\"logs\"", "", "")
			.replace_first("init = |_| ({}, [])", "init = |_| ({}, [Effect.send(\"project/note_this\", [])])")
	write!(ctx, "client/app.roc", source)?
	without = joy_ok!(ctx, ["build"], 1)?
	contains(without, "It goes in a new file beside the module,\nclient/app.js, and starts like this:\n\n    //// effect project/note_this\n")?
	contains(without, "[Effect.send(\"project/note_this\", [])])\n")?
	javascript = "//// effect project/note_this\ndefineEffect('project/note_this', () => console.log('noted'));\n"
	write!(ctx, "client/app.js", javascript)?
	_ = joy_ok!(ctx, ["build"], 0)?
	contains(read!(ctx, "dist/client/effects.js")?, "project/note_this")?

	_ = Path.utf8("${ctx.dir}/client/app.js").delete!()
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "app failed", 1)?
	port = port_after(dev1.out, "Starting on http://localhost")?
	events = expect_event!(listen!(port)?, "failed", 1)?
	write!(ctx, "client/app.js", javascript)?
	dev2 = wait_for!(dev1, "built app", 1)?
	fixed = expect_event!(events, "fixed", 1)?
	_ = expect_event!(fixed, "runtime", 1)?
	served = read!(ctx, ".joy/dev/client/effects.js")?
	_ = stop_dev!(dev2)?
	contains(dev2.out, "client/app.js changed")?
	contains(served, "project/note_this")
}

## A package that does not load stops roc early, before it has read the
## files the bundle is made of. ./joy dev still builds again when the package
## is put right, and when another of the bundle's files is saved meanwhile.
dev_package_recovers! : Ctx => Try({}, [Failed(Str)])
dev_package_recovers! = |ctx| {
	greeter!(ctx, "Effect.send(\"greeter/say_hello\", Wire.writer({}).str(name).done())", "Greeter.greet(\"you\")")?
	header = read!(ctx, "greeter/main.roc")?
	dev = start_dev!(ctx, ["--port", "0"], [])?
	dev1 = wait_for!(dev, "Ready on", 1)?
	write!(ctx, "greeter/main.roc", "package [Greeter] { pf: platform \"no/such/platform/main.roc\" }\n")?
	dev2 = wait_for!(dev1, "app failed", 1)?
	write!(ctx, "greeter/main.roc", header)?
	dev3 = wait_for!(dev2, "built app", 2)?

	# The same for a package under client/, and a save elsewhere while it is broken.
	write!(ctx, "greeter/main.roc", "package [Greeter { pf: platform \"${platform_from(ctx, "greeter/main.roc")}\" }\n")?
	dev4 = wait_for!(dev3, "app failed", 2)?
	write!(ctx, "greeter/main.roc", header)?
	dev5 = wait_for!(dev4, "built app", 3)?
	_ = stop_dev!(dev5)?
	Ok({})
}

## What the check holds whatever the source looks like, as it goes by the
## wasm: a call under another name, by an import's `as` or `exposing`, and an
## id of any length. roc refuses an id with letters a build could not read.
## A section whose `////` line and code name two ids is refused, and so is a
## call on JavaScript of the other kind.
effect_checks! : Ctx => Try({}, [Failed(Str)])
effect_checks! = |ctx| {
	starting = |import_line, effect|
		app_source(platform_from(ctx, "client/app.roc"), "\"checks\"", import_line, "")
			.replace_first("init = |_| ({}, [])", "init = |_| ({}, [${effect}])")
	write!(ctx, "client/app.roc", starting("import pf.Effect as Fx", "Fx.send(\"project/no_such_thing\", [])").replace_each("List(Effect(Msg))", "List(Fx.Effect(Msg))").replace_first("import pf.Effect\n", ""))?
	renamed = joy_ok!(ctx, ["build"], 1)?
	contains(renamed, "custom effect without javascript")?
	contains(renamed, "[Fx.send(\"project/no_such_thing\", [])])\n")?

	write!(ctx, "client/app.roc", starting("import pf.Effect exposing [send]", "send(\"project/no_such_thing\", [])").replace_first("import pf.Effect\n", ""))?
	bare = joy_ok!(ctx, ["build"], 1)?
	contains(bare, "custom effect without javascript")?
	contains(bare, "[send(\"project/no_such_thing\", [])])\n")?

	write!(ctx, "client/app.roc", starting("", "Effect.send(\"a/b\", [])"))?
	short = joy_ok!(ctx, ["build"], 1)?
	contains(short, "custom effect without javascript")?
	contains(short, "[Effect.send(\"a/b\", [])])\n                                  ^^^\n")?
	write!(ctx, "client/app.js", "//// effect a/b\ndefineEffect('a/b', () => {});\n")?
	_ = joy_ok!(ctx, ["build"], 0)?
	contains(read!(ctx, "dist/client/effects.js")?, "defineEffect('a/b'")?

	write!(ctx, "client/app.roc", starting("", "Effect.send(\"my app\", [])"))?
	spaced = joy_ok!(ctx, ["build"], 1)?
	contains(spaced, "The id of an effect is made of letters, digits and _ - . / only, like")?

	write!(ctx, "client/app.roc", starting("", "Effect.send(\"project/buzz_once\", [])"))?
	write!(ctx, "client/app.js", "//// effect project/buzz_once\ndefineEffect('project/buzz_twice', () => {});\n")?
	drifted = joy_ok!(ctx, ["build"], 1)?
	contains(drifted, "custom effect section without its code")?
	contains(drifted, "    //// effect project/buzz_once\n    defineEffect('project/buzz_once', ...")?

	write!(ctx, "client/app.js", "//// subscription project/buzz_once\ndefineSubscription('project/buzz_once', () => () => {});\n")?
	other = joy_ok!(ctx, ["build"], 1)?
	contains(other, "custom effect of the other kind")?
	contains(other, "Effect.call or Effect.send needs a section that starts with\n`//// effect project/buzz_once` and `defineEffect`.")?

	# What is wrong in the JavaScript itself, whatever the app uses of it.
	write!(ctx, "client/app.js", "import x from 'x';\n//// effect project/buzz_once\ndefineEffect('project/buzz_once', () => x);\n")?
	importing = joy_ok!(ctx, ["build"], 1)?
	contains(importing, "custom effect file with an import line")?
	contains(importing, " client/app.js:1\n")?
	write!(ctx, "client/app.js", "// about\n//// efect project/buzz_once\ndefineEffect('project/buzz_once', () => {});\n")?
	odd = joy_ok!(ctx, ["build"], 1)?
	contains(odd, "custom effect line not understood")?
	contains(odd, " client/app.js:2\n")?
	write!(ctx, "client/app.js", "defineEffect('project/buzz_once', () => {});\n")?
	bare_code = joy_ok!(ctx, ["build"], 1)?
	contains(bare_code, "custom effect code without its line")?
	contains(bare_code, "    //// effect project/buzz_once\n    defineEffect('project/buzz_once', ...")?
	write!(ctx, "client/app.js", "//// effect project/buzz_once\ndefineEffect('project/buzz_once', () => {});\n//// effect joy/http/send\ndefineEffect('joy/http/send', () => {});\n")?
	taken = joy_ok!(ctx, ["build"], 1)?
	contains(taken, "custom effect with an id of joy's")?
	contains(taken, "custom effect defined twice")?
	contains(taken, "The other one is in Joy itself.")?

	# Code at the top of the file is there for its sections, and the file
	# ships as it is written: a build takes Joy's own lines apart, not these.
	shared = "const note = `\n  // kept\n  as written`;\n\n//// effect project/buzz_once\ndefineEffect('project/buzz_once', () => note);\n\n//// effect project/never_used\ndefineEffect('project/never_used', () => 0);\n"
	write!(ctx, "client/app.js", shared)?
	built = joy_ok!(ctx, ["build"], 0)?
	contains(built, "  with custom effects from client/app.js\n")?
	runtime = read!(ctx, "dist/client/effects.js")?
	contains(runtime, "const note = `\n  // kept\n  as written`;")?
	contains(runtime, "defineEffect('project/buzz_once', () => note);")?
	lacks(runtime, "project/never_used")?

	# The custom effects are a module of their own, handed what they may use
	# and nothing else. runtime.js loads it by its hashed name.
	contains(runtime, "export default ({ defineEffect, defineSubscription, WireWriter }) => {")?
	joys = read!(ctx, "dist/client/runtime.js")?
	lacks(joys, "defineEffect('project/buzz_once'")?
	contains(joys, "loadCustomEffects(() => import('./effects.")?
	named = (joys.split_on("import('./").last() ?? "").split_on("'").first() ?? ""
	check(read!(ctx, "dist/client/${named}")? == runtime, "runtime.js names ${named}, which is not the custom effects")
}

## Two bundles that use one module with a custom effect of the project's own.
## Side by side in client/ they import the module. In folders of their own
## they cannot, as a roc import stays below the app's folder, so the module
## is a package the two name. Under client/ that package is found twice, as
## the project's files and as a package's, and counts once.
shared_feature! : Ctx => Try({}, [Failed(Str)])
shared_feature! = |ctx| {
	confetti = |id| "import pf.Effect\n\nConfetti := [].{\n\tburst : U64 -> Effect(msg)\n\tburst = |_pieces| Effect.send(\"${id}\", [])\n}\n"
	write!(ctx, "client/effects/Confetti.roc", confetti("project/confetti"))?
	write!(ctx, "client/effects/Confetti.js", "//// effect project/confetti\ndefineEffect('project/confetti', () => console.log('confetti'));\n")?
	beside = |bundle_file|
		app_source(platform_from(ctx, bundle_file), "\"bursts\"", "import /effects/Confetti as Confetti", "")
			.replace_first("init = |_| ({}, [])", "init = |_| ({}, [Confetti.burst(3)])")
	write!(ctx, "client/shop.roc", beside("client/shop.roc"))?
	write!(ctx, "client/admin.roc", beside("client/admin.roc"))?
	_ = joy_ok!(ctx, ["build"], 0)?
	contains(read!(ctx, "dist/client/effects.js")?, "project/confetti")?

	_ = Path.utf8("${ctx.dir}/client/shop.roc").delete!()
	_ = Path.utf8("${ctx.dir}/client/admin.roc").delete!()
	write!(ctx, "client/effects/main.roc", "package [Confetti] { pf: platform \"${platform_from(ctx, "client/effects/main.roc")}\" }\n")?
	through = |bundle_file|
		app_source(platform_from(ctx, bundle_file), "\"bursts\"", "import effects.Confetti", "")
			.replace_first("\thtml: ", "\teffects: \"../effects/main.roc\",\n\thtml: ")
			.replace_first("init = |_| ({}, [])", "init = |_| ({}, [Confetti.burst(3)])")
	write!(ctx, "client/shop/main.roc", through("client/shop/main.roc"))?
	write!(ctx, "client/admin/main.roc", through("client/admin/main.roc"))?
	_ = joy_ok!(ctx, ["build"], 0)?
	runtime = read!(ctx, "dist/client/effects.js")?
	check(runtime.split_on("defineEffect('project/confetti'").len() == 2, "runtime.js has the shared custom effect ${(runtime.split_on("defineEffect('project/confetti'").len() - 1).to_str()} times")?
	write!(ctx, "client/effects/Confetti.roc", confetti("project/confety"))?
	refused = joy_ok!(ctx, ["build"], 1)?
	check(refused.split_on("custom effect without javascript").len() == 2, "the shared module's call is reported more than once:\n${refused}")?
	contains(refused, "Did you mean this one?\n\n    project/confetti\n\nIf the id")?
	contains(refused, "\nin client/effects/Confetti.js.")
}

## The app of the guide's Custom effects topic, on this checkout's platform.
## A build checks what roc cannot: that each id its Roc calls is defined by
## the JavaScript beside it.
guide_custom_effects! : Ctx => Try({}, [Failed(Str)])
guide_custom_effects! = |ctx| {
	for file in ["client/main.roc", "client/effects/main.roc", "client/effects/Locale.roc", "client/effects/Locale.js", "client/effects/Share.roc", "client/effects/Share.js", "client/effects/Network.roc", "client/effects/Network.js"] {
		source = Path.utf8("${ctx.joy_root}/guide/samples/custom_effects/${file}").read_utf8!() ? |_| Failed("could not read the guide's ${file}")
		named =
			match source.split_first("pf: platform \"") {
				Ok({ after, .. }) => after.split_on("\"").first() ?? ""
				Err(_) => ""
			}
		write!(ctx, file, if (named == "") source else source.replace_first("pf: platform \"${named}\"", "pf: platform \"${platform_from(ctx, file)}\""))?
	}
	_ = joy_ok!(ctx, ["build"], 0)?
	runtime = read!(ctx, "dist/client/effects.js")?
	contains(runtime, "defineEffect('my_app/locale_get'")?
	contains(runtime, "defineEffect('my_app/share_link'")?
	contains(runtime, "defineSubscription('my_app/network_changes'")
}

## The counter at the top of the README, on this checkout's platform.
readme_example! : Ctx => Try({}, [Failed(Str)])
readme_example! = |ctx| {
	readme = Path.utf8("${ctx.joy_root}/README.md").read_utf8!() ? |_| Failed("could not read README.md")
	source =
		match readme.split_first("```roc\n") {
			Ok({ after, .. }) =>
				match after.split_first("\n```") {
					Ok({ before, .. }) => before
					Err(_) => return Err(Failed("the README's example does not end"))
				}
			Err(_) => return Err(Failed("the README has no roc example"))
		}
	release =
		match source.split_first("pf: platform \"") {
			Ok({ after, .. }) => after.split_on("\"").first() ?? ""
			Err(_) => return Err(Failed("the README's example names no platform:\n${source}"))
		}
	check(release.starts_with("https://") and release.ends_with(".tar.zst"), "the README's example does not name a release: ${release}")?
	write!(ctx, "client/counter.roc", source.replace_first(release, platform_from(ctx, "client/counter.roc")))?
	built = joy_ok!(ctx, ["build"], 0)?
	contains(built, "Built 1 bundle")
}

# ./joy upgrade

joy_release = |tag| "https://github.com/niclas-ahden/joy/releases/download/${tag}/P${tag.replace_each(".", "")}.tar.zst"

html_release = |tag| "https://github.com/niclas-ahden/joy-html/releases/download/${tag}/H${tag.replace_each(".", "")}.tar.zst"

carousel_release = "https://github.com/niclas-ahden/joy-carousel/releases/download/0.3.0/Car.tar.zst"

## A project on Joy `tag`: a bundle, a custom effects package and a server,
## and a versions.json that lists releases up to 0.45.0, each with ./joy's
## source in this checkout as its CLI. Returns the environment that reads it.
upgrade_project! : Ctx, Str => Try(List((Str, Str)), [Failed(Str)])
upgrade_project! = |ctx, tag| {
	write!(
		ctx,
		"client/app.roc",
		Str.join_with(
			[
				"app [Model, Msg, init, update, view, subscriptions] {",
				"\tpf: platform \"${joy_release(tag)}\",",
				"\thtml: \"${html_release("0.18.0")}\",",
				"\tcar: \"${carousel_release}\",",
				"\teffects: \"effects/main.roc\",",
				"}",
				"",
				"import html.Html",
				"",
				"# ${joy_release(tag)} stays, outside the header.",
				"",
			],
			"\n",
		),
	)?
	write!(ctx, "client/effects/main.roc", "package [Share] { pf: platform \"${joy_release(tag)}\" }\n")?
	write!(ctx, "server/main.roc", "app [main!] {\n\tpf: platform \"${cli_platform}\",\n\thtml: \"${html_release("0.18.0")}\",\n}\n")?
	tags = ["0.45.0", "0.44.1", "0.44.0", "0.40.0", "0.37.0", "0.36.1", "0.36.0", "0.36.0-rc2", "0.35.2", "0.35.1", "0.35.0"]
	entries = tags.map(
		|t| {
			# Releases from before Roc made releases name a nightly instead.
			(nightly, minimum) = if (t.starts_with("0.35.")) ("nightly-2026-11-01-abc1234", "") else ("", "0.1.0-rc1")
			"{\"tag\":\"${t}\",\"date\":\"\",\"platform_url\":\"${joy_release(t)}\",\"cli_url\":\"${ctx.joy_root}/cli/main.roc\",\"html_url\":\"${html_release("0.19.0")}\",\"roc_nightly\":\"${nightly}\",\"roc_minimum\":\"${minimum}\",\"added_later\":\"\"}"
		},
	)
	write!(ctx, "versions.json", "{\"schema\":1,\"releases\":[${Str.join_with(entries, ",")}]}")?
	Ok([("JOY_VERSIONS_URL", "${ctx.dir}/versions.json"), ("JOY_UPGRADE_TO", "")])
}

upgrade_no_input! : Ctx => Try({}, [Failed(Str)])
upgrade_no_input! = |ctx| {
	env = upgrade_project!(ctx, "0.35.0")?
	before = read!(ctx, "client/app.roc")?
	listed = joy_with!(ctx, ["upgrade"], 1, env)?
	contains(
		listed,
		Str.join_with(
			[
				"This project is on Joy 0.35.0. Name the release to upgrade to:",
				"  0.35.2  Fixes only  https://github.com/niclas-ahden/joy/releases/tag/0.35.2",
				"  0.36.1  Next step   https://github.com/niclas-ahden/joy/releases/tag/0.36.0",
				"  ... 3 more, 0.37 to 0.44",
				"  0.45.0  Latest      https://github.com/niclas-ahden/joy/releases/tag/0.45.0",
				"",
				"    ./joy upgrade 0.45.0",
			],
			"\n",
		),
	)?
	# A candidate is only ever named.
	lacks(listed, "rc2")?
	after = read!(ctx, "client/app.roc")?
	check(before == after, "upgrade changed client/app.roc without being told a release")?
	# --no-input never asks, even at a terminal.
	_ = joy_with!(ctx, ["upgrade", "--no-input"], 1, env)?
	write!(ctx, "client/app.roc", before.replace_each(joy_release("0.35.0"), joy_release("0.45.0")))?
	latest = joy_with!(ctx, ["upgrade"], 0, env)?
	contains(latest, "This project is on Joy 0.45.0, the latest release.")
}

upgrade_moves! : Ctx => Try({}, [Failed(Str)])
upgrade_moves! = |ctx| {
	env = upgrade_project!(ctx, "0.35.0")?
	# The ./joy of the release it moves to does the work, which this one is
	# told it is.
	as_release = |tag| env.map(|(key, value)| if (key == "JOY_UPGRADE_TO") (key, tag) else (key, value))
	out = joy_with!(ctx, ["upgrade", "0.44.1"], 0, as_release("0.44.1"))?
	contains(
		out,
		Str.join_with(
			[
				"Upgraded to Joy 0.44.1.",
				"  client/app.roc           platform 0.35.0 -> 0.44.1, joy-html 0.18.0 -> 0.19.0",
				"  client/effects/main.roc  platform 0.35.0 -> 0.44.1",
				"  server/main.roc          joy-html 0.18.0 -> 0.19.0",
				"  ./joy                    installed",
				"",
				"Left as they are:",
			],
			"\n",
		),
	)?
	contains(out, "  joy-carousel 0.3.0      client/app.roc\n")?
	contains(out, "  joy-cli-platform 0.1.0  server/main.roc\n")?
	contains(out, "Joy 0.44.1 needs Roc 0.1.0-rc1 or later.")?
	contains(out, "Run ./joy dev to see what needs changing. Read the notes from 0.36.0 to 0.44.0: https://github.com/niclas-ahden/joy/releases")?
	app_file = read!(ctx, "client/app.roc")?
	contains(app_file, "pf: platform \"${joy_release("0.44.1")}\"")?
	contains(app_file, "html: \"${html_release("0.19.0")}\"")?
	contains(app_file, "car: \"${carousel_release}\"")?
	contains(app_file, "# ${joy_release("0.35.0")} stays, outside the header.")?
	contains(read!(ctx, "client/effects/main.roc")?, joy_release("0.44.1"))?
	server = read!(ctx, "server/main.roc")?
	contains(server, html_release("0.19.0"))?
	contains(server, cli_platform)?
	check(Path.utf8("${ctx.dir}/joy").is_executable!() ?? False, "upgrade did not install ./joy")?
	# An older release can be named too.
	older = joy_with!(ctx, ["upgrade", "0.35.1"], 0, as_release("0.35.1"))?
	contains(older, "Moved back to Joy 0.35.1, from the newer 0.44.1.")?
	contains(read!(ctx, "client/app.roc")?, joy_release("0.35.1"))?
	again = joy_with!(ctx, ["upgrade", "0.35.1"], 0, as_release("0.35.1"))?
	contains(again, "This project is on Joy 0.35.1 already.")
}

upgrade_hands_off! : Ctx => Try({}, [Failed(Str)])
upgrade_hands_off! = |ctx| {
	env = upgrade_project!(ctx, "0.35.0")?
	out = joy_with!(ctx, ["upgrade", "0.35.2"], 0, env)?
	contains(out, "Building ./joy for Joy 0.35.2, which does the upgrade.\nUpgraded to Joy 0.35.2.")?
	contains(out, "Notes: https://github.com/niclas-ahden/joy/releases/tag/0.35.2")?
	lacks(out, "Run ./joy dev")?
	contains(read!(ctx, "client/app.roc")?, joy_release("0.35.2"))?
	check(!exists!(ctx, ".joy/upgrade"), "upgrade left the ./joy it built behind")?
	check(Path.utf8("${ctx.dir}/joy").is_executable!() ?? False, "upgrade did not install ./joy")?
	# The ./joy of a release that does not build changes nothing.
	write!(ctx, "versions.json", read!(ctx, "versions.json")?.replace_each("${ctx.joy_root}/cli/main.roc", "${ctx.dir}/missing/main.roc"))?
	failed = joy_with!(ctx, ["upgrade", "0.36.1"], 1, env)?
	contains(failed, "Could not build ./joy for Joy 0.36.1, so nothing changed.")?
	contains(failed, "Joy 0.36.1 needs Roc 0.1.0-rc1 or later.")?
	contains(read!(ctx, "client/app.roc")?, joy_release("0.35.2"))
}

upgrade_refuses! : Ctx => Try({}, [Failed(Str)])
upgrade_refuses! = |ctx| {
	env = upgrade_project!(ctx, "0.35.0")?
	unknown = joy_with!(ctx, ["upgrade", "9.9.9"], 1, env)?
	contains(unknown, "There is no Joy release called 9.9.9. The releases are at https://github.com/niclas-ahden/joy/releases")?
	bundle!(ctx, "client/app.roc", "on a checkout")?
	_ = Path.utf8("${ctx.dir}/client/effects/main.roc").delete!()
	checkout = joy_with!(ctx, ["upgrade"], 1, env)?
	contains(checkout, "client/app.roc builds against the Joy checkout at ")?
	_ = Path.utf8("${ctx.dir}/client/app.roc").delete!()
	_ = Path.utf8("${ctx.dir}/server/main.roc").delete!()
	nothing = joy_with!(ctx, ["upgrade"], 1, env)?
	contains(nothing, "No .roc file here names a Joy release.")
}

## The list at a terminal, through script(1), which runs ./joy on a pseudo
## terminal and passes it the keys written here, one at a time.
upgrade_at_terminal! : Ctx => Try({}, [Failed(Str)])
upgrade_at_terminal! = |ctx| {
	env = upgrade_project!(ctx, "0.35.0")?
	before = read!(ctx, "client/app.roc")?
	# Escape leaves everything as it was.
	cancelled = at_terminal!(ctx, env, ["\u(1b)"])?
	contains(cancelled, "? Upgrade to which release? (cancelled)")?
	check(read!(ctx, "client/app.roc")? == before, "a cancelled upgrade changed client/app.roc")?
	# Stay, 0.35.2, 0.36.1, then the gap, which opens on 0.37.0.
	here = env.map(|(name, value)| if (name == "JOY_UPGRADE_TO") (name, "0.37.0") else (name, value))
	picked = at_terminal!(ctx, here, ["j", "j", "j", "\r", "\r"])?
	contains(picked, "  ... 3 more, 0.37 to 0.44")?
	contains(picked, "? Upgrade to which release? 0.37.0")?
	contains(picked, "Upgraded to Joy 0.37.0.")?
	contains(read!(ctx, "client/app.roc")?, joy_release("0.37.0"))
}

## Run ./joy upgrade at a pseudo terminal, press `keys` and return what it
## printed.
at_terminal! : Ctx, List((Str, Str)), List(Str) => Try(Str, [Failed(Str)])
at_terminal! = |ctx, envs, keys| {
	line = "stty cols 120 rows 30; ${ctx.joy} upgrade"
	# util-linux's script, on Linux, knows --version and takes the command
	# with -c. The BSD one, on macOS, takes it after the file.
	args = if (has_tool!("script")) ["-qfc", line, "/dev/null"] else ["-q", "/dev/null", "sh", "-c", line]
	child =
		Cmd.new(OsStr.from_str("script"))
			.args(args.map(OsStr.from_str))
			.envs(envs.map(|(name, value)| (OsStr.from_str(name), OsStr.from_str(value))))
			# ./joy never asks with CI set, which CI runners do.
			.env(OsStr.from_str("CI"), OsStr.from_str(""))
			.cwd(Path.utf8(ctx.dir))
			.stdin(Pipe)
			.stdout(Pipe)
			.stderr(MergeWithStdout)
			.spawn_leashed!()
			? |err| Failed("script did not start: ${Str.inspect(err)}")
	var $out = ""
	var $left = keys
	var $quiet = 0
	started = Monotonic.now!()
	# A key is pressed once the list is drawn, then each after the output
	# settles, so each arrives as a read of its own, as typing makes it.
	while True {
		if Monotonic.since(Monotonic.now!(), started).to_millis() > 60_000 {
			_ = child.kill!()
			return Err(Failed("./joy upgrade at a terminal never finished:\n${$out}"))
		}
		match child.read!(Duration.millis(100)) {
			Ok(Stdout(bytes)) | Ok(Stderr(bytes)) => {
				$out = Str.concat($out, Str.from_utf8_lossy(bytes))
				$quiet = 0
			}
			Err(EndOfInput) => break
			Err(_) => {
				$quiet = $quiet + 1
			}
		}
		match $left {
			[pressed, .. as rest] if $quiet >= 3 and $out.contains("? Upgrade to which release?") => {
				child.write_bytes!(Str.to_utf8(pressed), Duration.seconds(5)) ? |err| Failed("could not press a key: ${Str.inspect(err)}")
				$left = rest
				$quiet = 0
			}
			_ => {}
		}
	}
	_ = child.wait!()
	Ok($out.replace_each("\u(1b)[2K", ""))
}

upgrade_all_or_nothing! : Ctx => Try({}, [Failed(Str)])
upgrade_all_or_nothing! = |ctx| {
	env = upgrade_project!(ctx, "0.35.0")?
	here = env.map(|(name, value)| if (name == "JOY_UPGRADE_TO") (name, "0.36.1") else (name, value))
	write!(ctx, "scripts/check.roc", "#!/usr/bin/env roc\napp [main!] {\n\tpf: platform \"${cli_platform}\",\n\thtml: \"${html_release("0.18.0")}\",\n}\n")?
	chmod!(ctx, "755", "scripts/check.roc")?
	before = read!(ctx, "client/app.roc")?
	# A folder ./joy cannot write in stops the upgrade before any file moves.
	chmod!(ctx, "555", "client/effects")?
	refused = joy_with!(ctx, ["upgrade", "0.36.1"], 1, here)?
	chmod!(ctx, "755", "client/effects")?
	contains(refused, "Could not write client/effects/main.roc, so nothing changed.")?
	check(read!(ctx, "client/app.roc")? == before, "a refused upgrade changed client/app.roc")?
	check(!exists!(ctx, "client/app.roc.upgrade") and !exists!(ctx, "scripts/check.roc.upgrade"), "a refused upgrade left its copies behind")?
	_ = joy_with!(ctx, ["upgrade", "0.36.1"], 0, here)?
	contains(read!(ctx, "scripts/check.roc")?, html_release("0.19.0"))?
	check(Path.utf8("${ctx.dir}/scripts/check.roc").is_executable!() ?? False, "upgrade lost the mode of scripts/check.roc")
}
