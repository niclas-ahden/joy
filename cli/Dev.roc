import pf.Cmd
import pf.Duration
import pf.Env
import pf.Events
import pf.Http
import pf.Monotonic
import pf.OsStr
import pf.Path
import pf.Server
import pf.Signal
import pf.Sse
import pf.Stderr
import pf.Stdout
import pf.Utc
import pf.Watch
import http.Request
import http.Response
import weaver.Cli
import weaver.Opt
import weaver.SubCmd
import Args
import Build
import Compile
import Generated
import JsonText
import Project

## `./joy dev`: build every bundle, rebuild exactly the bundles a change
## reaches, and serve or start what the project needs, until Ctrl-C.
##
## Bundles build into .joy/dev/, never dist/, at --opt=size. Each build
## writes the files it read through roc's --watch-inputs-file, which is how a
## change finds the bundles and servers it reaches. A build goes to a staging
## folder first, and only a clean one replaces what pages load.
##
## Open pages hear about builds from the dev server's event stream, which the
## development runtime.js listens to: `hello` on connect, `reload` after a
## rebuild, `failed` with roc's report, `fixed`, and `asset` when a file in
## public/ or assets/ changes.
Dev :: [].{

	## The options of `./joy dev`.
	Options : {
		jobs : Try(Str, [NoValue]),
		serve_files : Bool,
		port : Try(Str, [NoValue]),
		events_port : Try(Str, [NoValue]),
		host : Try(Str, [NoValue]),
		server : List(Str),
		no_server : Bool,
		proxy : List(Str),
		client_url : Try(Str, [NoValue]),
		public_dir : Str,
		poll : Bool,
	}

	## `./joy dev` as a weaver subcommand, which also writes its --help.
	command : (Dev.Options -> command) -> SubCmd.SubcommandParserConfig(command)
	command = |wrap|
		SubCmd.finish(
			{
				jobs: Opt.maybe_str({ short: "", long: "jobs", help: "Builds at a time, 4 by default." }),
				serve_files: Opt.flag({ short: "", long: "serve-files", help: "Serve the files under the client URL and pass everything else to the project's server, as a proxy or a CDN in front of it does in production. Without it the server serves its own files. The server listens on $PORT, which ./joy picks when unset. ($JOY_SERVE_FILES=1)" }),
				port: Opt.maybe_str({ short: "", long: "port", help: "Where ./joy serves the pages, with --serve-files or when the project has no server, 8000 or the next free one. ($JOY_PORT)" }),
				events_port: Opt.maybe_str({ short: "", long: "events-port", help: "Where ./joy sends its events when the project's server serves the pages. ($JOY_EVENTS_PORT)" }),
				host: Opt.maybe_str({ short: "", long: "host", help: "The address to listen on, localhost by default. ($JOY_HOST)" }),
				server: Opt.str_list({ short: "", long: "server", help: "Start this server instead of server/main.roc, repeatable." }),
				no_server: Opt.flag({ short: "", long: "no-server", help: "Start no server, only the dev server." }),
				proxy: Opt.str_list({ short: "", long: "proxy", help: "PATH=URL: forward requests under PATH to a backend, repeatable. ($JOY_PROXY, space separated)" }),
				client_url: Opt.maybe_str({ short: "", long: "client-url", help: "Where the app serves client/, / by default. ($JOY_CLIENT_URL)" }),
				public_dir: Opt.str({ short: "", long: "public-dir", help: "The folder of files served as they are.", default: Value("public") }),
				poll: Opt.flag({ short: "", long: "poll", help: "Compare files on a timer, for filesystems that send no events." }),
			}.Cli,
			{
				name: "dev",
				description: "Build every bundle, rebuild what a change reaches, and serve or start what the project needs, until Ctrl-C. Anything after -- goes to roc.",
				mapper: wrap,
			},
		)

	## Run with `options`, and `roc` given to every roc build as it is.
	run! : Dev.Options, List(Str) => Try({}, _)
	run! = |options, roc| {
		jobs = Build.parse_jobs!(Args.given(options.jobs))?
		Signal.catch!([Interrupt])?
		root = Path.display(Env.cwd!()?)

		{ bundles, .. } = Project.find!()?
		servers =
			if options.no_server {
				[]
			} else {
				match options.server {
					[] =>
						match Project.server!() {
							Some(file) => [file]
							None => []
						}
					given => given
				}
			}
		if bundles.is_empty() and servers.is_empty() {
			return Build.fail!("There are no bundles under client/ and no server, so there is nothing to run.")
		}
		Build.check_releases!(bundles)?
		Build.ensure_hosts!(bundles)?
		for dir in [".joy/dev/client", ".joy/dev/inputs", ".joy/dev/staging", ".joy/dev/servers"] {
			Path.utf8(dir).create_all!()?
		}

		host = setting!(Args.given(options.host), "JOY_HOST") ?? "localhost"
		events = Events.new!({})
		session = Utc.to_millis_since_epoch(Utc.now!()).to_str()
		events.set_greeting!([hello(session, 0)])
		public_dir = options.public_dir.drop_suffix("/")
		client_url = Build.client_url!(Args.given(options.client_url))
		# With --serve-files a proxy or a CDN serves the files in production and
		# forwards the rest to the server, and ./joy dev plays that part.
		# Without it the server serves its own files.
		serve_files = !servers.is_empty() and (options.serve_files or switch!("JOY_SERVE_FILES")?)
		if serve_files and servers.len() > 1 {
			return Build.fail!("--serve-files passes the pages to one server, and there are ${servers.len().to_str()}.")
		}
		given_port =
			match Env.var_str!(OsStr.from_str("PORT")) {
				Ok(value) => Some(parse_port!(value)?)
				Err(_) => None
			}
		server_port =
			match given_port {
				None if serve_files => Some(free_port!({})?)
				other => other
			}
		behind =
			match server_port {
				Some(port) if serve_files => [("/", "http://127.0.0.1:${port.to_str()}")]
				_ => []
			}
		server_env =
			match server_port {
				Some(port) if serve_files => [("PORT", port.to_str())]
				_ => []
			}
		proxy_settings = (Env.var_str!(OsStr.from_str("JOY_PROXY")) ?? "").split_on(" ").drop_if(|part| part.is_empty())
		proxies = options.proxy.concat(proxy_settings).map_try!(parse_proxy!)?.concat(behind)
		roots = ["client", "public", "assets"].keep_if_try!(|name| Ok(Path.utf8(root_dir(name, public_dir)).is_dir!() ?? False))?
		# The dev server is the front door when no server serves the pages, or
		# when it forwards to one. With --no-server the project's own server runs
		# on its own, so the dev server only sends events.
		no_server = options.no_server
		front_door = (servers.is_empty() and !no_server) or !proxies.is_empty()
		site = { client_url, public_dir, roots, proxies, fallback: servers.is_empty() and !no_server }
		dev_server = start_dev_server!(options, host, events, site, front_door)?
		dev_port = dev_server.port()
		if front_door {
			Stdout.line!("Serving the pages on http://${host}:${dev_port.to_str()}/")?
			match server_port {
				Some(port) if serve_files => Stdout.line!("  the files under ${client_url} from the builds, and everything else from the server on ${port.to_str()}")?
				_ => {}
			}
		} else {
			Stdout.line!("The dev server sends events on http://${host}:${dev_port.to_str()}/.joy/events")?
		}

		write_dev_files!(bundles, dev_port, public_dir, client_url)?
		names = servers.map(server_name)
		# Dev builds swap in nothing but what follows `--`, so every job has the
		# same caches, see Compile.cache_root!.
		caches = Compile.cache_root!(roc)?
		bundle_jobs = bundles.map(|bundle| bundle_job(bundle, roc, caches))
		server_jobs = servers.map(|file| server_job(file, server_name(file), roc, caches))
		# Watch before building, so a file saved while the first builds run is
		# not lost. The folders the builds read are known once they have run.
		before = watch_config!(root, bundles, servers, public_dir, options.poll)?
		watch = Watch.start!({ folders: before.folders, trees: before.trees, skip: before.skip, poll: before.poll })?
		Stdout.line!("Building ${(bundle_jobs.len() + server_jobs.len()).to_str()}, ${jobs.to_str()} at a time")?
		results = Compile.run_all!(server_jobs.concat(bundle_jobs), jobs, |result| handle_result!(result, events, session, 0).map_ok(|_| {}))?
		failed = results.keep_if(|result| result.outcome == Failed).map(|result| result.job.name)
		var $children = []
		for name in names {
			if !failed.contains(name) {
				$children = $children.append(start_server!(root, name, server_env)?)
			}
		}

		# A server that serves its own files is asked for the loader once it
		# runs, see check_server!.
		check =
			match given_port {
				Some(port) if !serve_files and port != 0 and !names.is_empty() => if ($children.is_empty()) Waiting(port) else Pending({ port, since: Monotonic.now!() })
				_ => Done
			}
		watched = watch_config!(root, bundles, servers, public_dir, options.poll)?
		watch.set!({ folders: watched.folders, trees: watched.trees, skip: watched.skip, poll: watched.poll })?
		outcome = loop!({
			root,
			bundles,
			servers,
			names,
			public_dir,
			events,
			session,
			build: 0,
			failed,
			queued: [],
			compile: { queue: [], running: [], done: [] },
			children: $children,
			server_env,
			client_url,
			check,
			watch,
			poll: options.poll,
			jobs,
			roc,
			caches,
		})
		for child in $children {
			child.process.close!() ?? {}
		}
		Server.stop!(dev_server)
		outcome
	}
}

DevState : {
	root : Str,
	bundles : List(Project.Bundle),
	servers : List(Str),
	names : List(Str),
	public_dir : Str,
	events : Events,
	session : Str,
	build : U64,
	failed : List(Str),
	queued : List(Str),
	compile : Compile.State,
	children : List(Started),

	## What a started server gets in its environment besides ./joy's own.
	server_env : List((Str, Str)),
	client_url : Str,

	## The server on $PORT, before it starts and while ./joy waits for it to
	## answer, see check_server!.
	check : [Waiting(U16), Pending({ port : U16, since : Monotonic }), Done],
	watch : Watch,
	poll : Bool,
	jobs : U64,
	roc : List(Str),

	## The roc caches of the builds, see Compile.cache_root!.
	caches : Str,
}

## A server ./joy started, and the part of a line it has printed so far.
Started : { name : Str, process : Cmd.Child, pending : Str }

loop! : DevState => Try({}, _)
loop! = |initial| {
	var $state = initial
	var $stopped = False
	while !$stopped {
		busy = !$state.compile.running.is_empty() or !$state.compile.queue.is_empty()
		timeout = if (busy) Duration.millis(50) else Duration.millis(250)
		match $state.watch.next!({ timeout: timeout }) {
			Ok(changes) => {
				$state = react!($state, changes)?
			}
			Err(Interrupted) => {
				$stopped = True
			}
			Err(err) => return Err(err)
		}
		if !$stopped {
			$state = step_builds!($state)?
			$state = { ..$state, children: $state.children.map_try!(forward_output!)? }
			$state = check_server!($state)?
		}
	}
	# Acknowledge Ctrl-C, or every effect after it is interrupted too.
	_ = Signal.poll!()
	Stdout.line!("Stopped")?
	Ok({})
}

## Queue the builds the changes reach, and tell pages about changed files in
## public/ and assets/.
react! : DevState, List(Watch.Change) => Try(DevState, _)
react! = |state, changes| {
	paths = changes.map(|change| Path.display(change.path))
	var $state = state
	# A bundle that appears or disappears changes the list of bundles.
	if paths.any(|path| path.starts_with("${state.root}/client/") and path.ends_with(".roc")) {
		$state = rediscover!($state)?
	}
	# A file that appears or disappears in assets/ or the public folder changes
	# assets.json and generated/. Its pages reload when what reads them rebuilds.
	if changes.any(|change| change.kind != Modified and [state.public_dir, "assets"].any(|dir| Path.display(change.path).starts_with("${state.root}/${dir}/"))) {
		write_dev_files!($state.bundles, 0, state.public_dir, state.client_url)?
	}
	for path in paths {
		for prefix in [state.public_dir, "assets"] {
			if path.starts_with("${state.root}/${prefix}/") {
				file = path.drop_prefix("${state.root}/${prefix}/")
				_ = state.events.publish!(Sse.Event.named("asset", [file]))
				Stdout.line!("${prefix}/${file} changed")?
			}
		}
	}
	reached = $state.bundles.map(|bundle| bundle.id).concat($state.names).keep_if_try!(|name| Ok(inputs_reach!(name, paths)))?
	queued = reached.keep_if(|name| !$state.queued.contains(name))
	Ok({ ..$state, queued: $state.queued.concat(queued) })
}

## Find the bundles again, build the new ones and forget the removed ones.
rediscover! : DevState => Try(DevState, _)
rediscover! = |state| {
	{ bundles, .. } = Project.find!()?
	old_ids = state.bundles.map(|bundle| bundle.id)
	new_ids = bundles.map(|bundle| bundle.id)
	for id in old_ids {
		if !new_ids.contains(id) {
			_ = Path.utf8(".joy/dev/client/${id}").delete_all!()
			Stdout.line!("${id} is no longer a bundle")?
		}
	}
	added = new_ids.keep_if(|id| !old_ids.contains(id))
	write_dev_files!(bundles, 0, state.public_dir, state.client_url)?
	Ok({ ..state, bundles, queued: state.queued.concat(added.keep_if(|id| !state.queued.contains(id))) })
}

## Start the queued builds that are not running already, and handle the ones
## that finished.
step_builds! : DevState => Try(DevState, _)
step_builds! = |state| {
	running_names = state.compile.running.map(|running| running.job.name)
	ready = state.queued.keep_if(|name| !running_names.contains(name))
	waiting = state.queued.keep_if(|name| running_names.contains(name))
	jobs = ready.keep_oks(|name| job_for(state, name))
	compile = Compile.step!({ ..state.compile, queue: state.compile.queue.concat(jobs), done: [] }, state.jobs)?
	var $state = { ..state, compile, queued: waiting }
	for result in compile.done {
		build = $state.build + 1
		outcome = handle_result!(result, $state.events, $state.session, build)?
		was_failing = $state.failed.contains(result.job.name)
		match outcome {
			Built => {
				$state = { ..$state, build, failed: $state.failed.drop_if(|name| name == result.job.name) }
				if $state.names.contains(result.job.name) {
					$state = restart_server!($state, result.job.name)?
				}
				$state.events.set_greeting!([hello($state.session, build)])
				if was_failing {
					_ = $state.events.publish!(Sse.Event.named("fixed", [result.job.name]))
					{}
				}
				_ = $state.events.publish!(Sse.Event.named("reload", [result.job.name]))
				{}
			}
			Failed => {
				$state = { ..$state, failed: if (was_failing) $state.failed else $state.failed.append(result.job.name) }
			}
		}
	}
	if !compile.done.is_empty() {
		# The builds may read other files now, so the watch follows them.
		watched = watch_config!($state.root, $state.bundles, $state.servers, $state.public_dir, $state.poll)?
		$state.watch.set!({ folders: watched.folders, trees: watched.trees, skip: watched.skip, poll: watched.poll })?
	}
	Ok($state)
}

job_for : DevState, Str -> Try(Compile.Job, [Gone])
job_for = |state, name|
	match state.bundles.find_first(|bundle| bundle.id == name) {
		Ok(bundle) => Ok(bundle_job(bundle, state.roc, state.caches))
		Err(_) =>
			match state.servers.find_first(|file| server_name(file) == name) {
				Ok(file) => Ok(server_job(file, name, state.roc, state.caches))
				Err(_) => Err(Gone)
			}
	}

## Put a clean build in place and report either outcome.
handle_result! : Compile.Result, Events, Str, U64 => Try([Built, Failed], _)
handle_result! = |result, events, _session, _build|
	match result.outcome {
		Built => {
			served = served_path(result.job)
			match served.split_last("/") {
				Ok({ before, .. }) => Path.utf8(before).create_all!()?
				Err(_) => {}
			}
			Path.utf8(result.job.output).rename!(Path.utf8(served))?
			if result.warnings.is_empty() {
				Stdout.line!("  built ${result.job.name}")?
			} else {
				# ./joy dev never fails on a warning: it is usually code still
				# being written.
				Stdout.line!("  built ${result.job.name}, with warnings:\n${result.log}")?
			}
			Ok(Built)
		}
		Failed => {
			Stderr.line!("  ${result.job.name} failed:\n${result.log}")?
			_ = events.publish!(Sse.Event.named("failed", [result.job.name, result.log]))
			Ok(Failed)
		}
	}

## Where pages and the server start find a clean build.
served_path : Compile.Job -> Str
served_path = |job| job.output.replace_first(".joy/dev/staging/", ".joy/dev/")

bundle_job : Project.Bundle, List(Str), Str -> Compile.Job
bundle_job = |bundle, roc, caches| {
	name: bundle.id,
	file: bundle.file,
	output: ".joy/dev/staging/client/${bundle.id}/app.wasm",
	args: Build.bundle_args("size", False, roc),
	inputs: ".joy/dev/inputs/${safe_name(bundle.id)}",
	cache: Compile.bundle_cache(caches),
	own_warnings_fail: False,
}

## A server builds at --opt=dev, roc's own backend: seconds where an LLVM
## build of a large server takes minutes.
server_job : Str, Str, List(Str), Str -> Compile.Job
server_job = |file, name, roc, caches| {
	name,
	file,
	output: ".joy/dev/staging/servers/${name}/main",
	args: ["build", "--opt=dev"].concat(roc),
	inputs: ".joy/dev/inputs/${safe_name(name)}",
	cache: Compile.server_cache(caches, name),
	own_warnings_fail: False,
}

server_name : Str -> Str
server_name = |file|
	if file == "server/main.roc" {
		"server"
	} else {
		file.drop_suffix(".roc").replace_each("/", "-")
	}

safe_name : Str -> Str
safe_name = |name| "${name.replace_each("/", "__")}.inputs"

## The files a build read, from roc's --watch-inputs-file: a magic line,
## then a path and its state, each ended by a zero byte.
inputs_of! : Str => List(Str)
inputs_of! = |name|
	match Path.utf8(".joy/dev/inputs/${safe_name(name)}").read_bytes!() {
		Ok(bytes) =>
			bytes
				.split_on(0)
				.drop_first(1)
				.map_with_index(|part, index| (part, index))
				.keep_if(|(_, index)| index % 2 == 0)
				.map(|(part, _)| Str.from_utf8_lossy(part))
				.keep_if(|path| !path.is_empty())
		Err(_) => []
	}

inputs_reach! : Str, List(Str) => Bool
inputs_reach! = |name, paths| {
	inputs = inputs_of!(name)
	paths.any(|path| inputs.contains(path) or inputs.any(|input| !input.starts_with("/") and path.ends_with("/${input}")))
}

## What to watch: the folders of every file a build read, apart from roc's
## package cache, and client/, public/ and assets/ whole.
watch_config! : Str, List(Project.Bundle), List(Str), Str, Bool => Try({ folders : List(Path), trees : List(Path), skip : List(Str), poll : [OsEvents, Every(Duration)] }, _)
watch_config! = |root, bundles, servers, public_dir, poll| {
	names = bundles.map(|bundle| bundle.id).concat(servers.map(server_name))
	folders =
		names
			.map_try!(|name| Ok(inputs_of!(name)))?
			.join()
			.map(|input| if (input.starts_with("/")) input else "${root}/${input}")
			.keep_oks(folder_of)
			.keep_if(|folder| !folder.contains("/.cache/roc/packages") and !folder.starts_with("${root}/client") and !folder.starts_with("${root}/${public_dir}") and !folder.starts_with("${root}/assets"))
	distinct = folders.fold([], |seen, folder| if (seen.contains(folder)) seen else seen.append(folder))
	existing = distinct.keep_if_try!(|folder| Ok(Path.utf8(folder).is_dir!() ?? False))?
	trees = ["client", public_dir, "assets"].keep_if_try!(|dir| Ok(Path.utf8(dir).is_dir!() ?? False))?
	Ok({
		folders: existing.map(Path.utf8),
		trees: trees.map(|dir| Path.utf8("${root}/${dir}")),
		skip: [".git", "dist", ".joy", "node_modules"],
		poll: if (poll) Every(Duration.millis(500)) else OsEvents,
	})
}

folder_of : Str -> Try(Str, [NoFolder])
folder_of = |file|
	match file.split_last("/") {
		Ok({ before, .. }) if !before.is_empty() => Ok(before)
		_ => Err(NoFolder)
	}

## What the dev server answers besides its event stream: the files under
## `client_url`, from the dev builds, assets/ and the public folder, the
## paths of each --proxy forwarded to its backend, and, with `fallback`,
## index.html for a page path, as a single-page app needs.
Site : {
	client_url : Str,
	public_dir : Str,
	roots : List(Str),
	proxies : List((Str, Str)),
	fallback : Bool,
}

## The dev server: the event stream, with CORS for pages another origin
## serves, and the files and proxies of `site`. As the front door it takes
## --port, 8000 or the next free one. Beside a server that serves the pages
## it takes the port it had last time, or one the system picks.
start_dev_server! : Dev.Options, Str, Events, Site, Bool => Try(Server, _)
start_dev_server! = |options, host, events, site, front_door| {
	if front_door {
		first = parse_port!(setting!(Args.given(options.port), "JOY_PORT") ?? "8000")?
		bind_from!(host, first, 100, events, site)
	} else {
		remembered = Path.utf8(".joy/events-port").read_utf8!() ?? "0"
		port = parse_port!(setting!(Args.given(options.events_port), "JOY_EVENTS_PORT") ?? remembered.trim())?
		server =
			match bind_from!(host, port, 0, events, site) {
				Ok(started) => started
				# The remembered port was taken meanwhile. Ask for another.
				Err(_) if port != 0 => bind_from!(host, 0, 0, events, site)?
				Err(err) => return Err(err)
			}
		Path.utf8(".joy/events-port").write_utf8!(server.port().to_str())?
		Ok(server)
	}
}

## Bind `port`, or the next free one, up to `tries` more.
bind_from! : Str, U16, U16, Events, Site => Try(Server, _)
bind_from! = |host, port, tries, events, site| {
	roots = site.roots.map(|name| { name, path: Path.utf8(root_dir(name, site.public_dir)), cache: Revalidate })
	match Server.start!({ host, port, roots }, |request| route!(events, site, request)) {
		Ok(server) => Ok(server)
		Err(ServerErr(AddrInUse)) if tries > 0 => bind_from!(host, port + 1, tries - 1, events, site)
		Err(err) => Err(err)
	}
}

root_dir : Str, Str -> Str
root_dir = |name, public_dir|
	match name {
		"client" => ".joy/dev/client"
		"public" => public_dir
		_ => name
	}

route! : Events, Site, Request.Request => Try(Server.Reply, _)
route! = |events, site, request| {
	path =
		match Request.uri(request).split_first("?") {
			Ok({ before, .. }) => before
			Err(_) => Request.uri(request)
		}
	if path == "/.joy/events" {
		return Ok(Server.stream(events, [{ name: "Access-Control-Allow-Origin", value: "*" }]))
	}
	if path.starts_with(site.client_url) {
		relative = path.drop_prefix(site.client_url)
		file = if (relative.is_empty() or relative.ends_with("/")) "${relative}index.html" else relative
		found = site.roots.keep_if_try!(|name| Ok(Path.utf8("${root_dir(name, site.public_dir)}/${file}").is_file!() ?? False))?
		match found.first() {
			Ok(name) => return Ok(Server.file(name, file))
			Err(_) => {}
		}
	}
	match site.proxies.keep_if(|(prefix, _)| under(path, prefix)).sort_with(|(a, _), (b, _)| longer_first(a, b)).first() {
		Ok((_, target)) => forward!(target, request)
		Err(_) =>
		# A path without an extension is a page, so an app that changes the
		# URL survives a refresh. A missing file with one is a 404, so a
		# module is never answered with HTML.
			if site.fallback and !has_extension(path) and site.roots.contains("public") {
				Ok(Server.file("public", "index.html"))
			} else {
				Ok(Server.respond(Response.from_status(404)))
			}
	}
}

## Whether `path` is `prefix` or below it.
under : Str, Str -> Bool
under = |path, prefix| prefix == "/" or path == prefix or path.starts_with("${prefix.drop_suffix("/")}/")

longer_first : Str, Str -> [Before, Same, After]
longer_first = |a, b| {
	(la, lb) = (a.count_utf8_bytes(), b.count_utf8_bytes())
	if (la > lb) Before else if (la < lb) After else Same
}

## Headers that belong to one connection, not to the request.
hop_by_hop = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer", "content-length"]

## Send a request on to a backend with its method, headers and body, and
## answer with what comes back. A local backend sees the browser's Host, as
## behind a reverse proxy, and a remote one its own. The whole answer is read
## before it is passed on, so streamed answers and WebSockets do not go
## through.
forward! : Str, Request.Request => Try(Server.Reply, _)
forward! = |target, request| {
	base = target.drop_suffix("/")
	local = ["http://localhost", "http://127.0.0.1", "http://[::1]"].any(|start| base.starts_with(start))
	headers = Request.headers(request).drop_if(|header| hop_by_hop.contains(header.name.with_ascii_lowercased()) or (!local and header.name.caseless_ascii_equals("host")))
	outgoing = request.with_uri("${base}${Request.uri(request)}").with_headers(headers)
	match Http.send!(outgoing, {}) {
		Ok(response) => Ok(Server.respond(response.with_headers(Response.headers(response).drop_if(|header| hop_by_hop.contains(header.name.with_ascii_lowercased())))))
		Err(err) => Ok(Server.respond(Response.from_status(502).with_body(Str.to_utf8("./joy dev could not reach ${base}: ${Str.inspect(err)}"))))
	}
}

has_extension : Str -> Bool
has_extension = |path|
	match path.split_last("/") {
		Ok({ after, .. }) => after.contains(".")
		Err(_) => path.contains(".")
	}

## The development joy.js and runtime.js, the latter with every feature and
## the listener for the dev server's events, and .joy/dev/assets.json, with
## every name plain and the folders the files live in.
write_dev_files! : List(Project.Bundle), U16, Str, Str => Try({}, _)
write_dev_files! = |bundles, dev_port, public_dir, client_url| {
	if dev_port != 0 and !bundles.is_empty() {
		runtime = Build.runtime!(bundles, Full)?
		Path.utf8(".joy/dev/client/runtime.js").write_utf8!("${runtime}\n${dev_client(dev_port)}")?
		Path.utf8(".joy/dev/client/joy.js").write_utf8!(Build.loader!(bundles)?)?
	}
	assets = Build.list_files!("assets")?
	public = Build.list_files!(public_dir)?
	json = JsonText.object([
		("roots", JsonText.object([("joy", JsonText.string("client")), ("assets", JsonText.string("../../assets")), ("public", JsonText.string("../../${public_dir}"))])),
		("joy", JsonText.string("joy.js")),
		("runtime", JsonText.string("runtime.js")),
		("bundles", JsonText.object(bundles.map(|bundle| (bundle.id, JsonText.string("${bundle.id}/app.wasm"))))),
		("assets", JsonText.object(assets.map(|file| (file, JsonText.string(file))))),
		("public", JsonText.array(public.map(JsonText.string))),
	])
	Path.utf8(".joy/dev/assets.json").write_utf8!("${json}\n")?
	# While you work generated/ maps every name to itself.
	if Generated.named!()? {
		match Generated.files(bundles, assets.map(|file| (file, file)), public, client_url) {
			Ok(contents) => {
				changed = Generated.write!("generated", contents)?
				if changed {
					Stdout.line!("Wrote generated/")?
				}
			}
			Err(SameTag(one, other)) => Stderr.line!("The bundles ${one} and ${other} would both be ${Project.tag_of(one)} in generated/Bundle.roc. Rename one of them.")?
		}
	}
	Ok({})
}

dev_client : U16 -> Str
dev_client = |port|
	dev_client_template.replace_each("JOY_DEV_PORT", port.to_str())

dev_client_template =
	\\// ./joy dev: reload the page when a build changes, and show failed
	\\// builds in the console. Only the development runtime.js has this.
	\\if (typeof window !== 'undefined' && typeof EventSource !== 'undefined' && !window.__joyDev) {
	\\  window.__joyDev = true;
	\\  const events = new EventSource(location.protocol + '//' + location.hostname + ':JOY_DEV_PORT/.joy/events');
	\\  const newline = String.fromCharCode(10);
	\\  let build = null;
	\\  // A restarted server needs a moment before it answers again.
	\\  const reload = async () => {
	\\    for (let tries = 0; tries < 100; tries++) {
	\\      try {
	\\        const answer = await fetch(location.href, { method: 'HEAD', cache: 'no-store' });
	\\        if (answer.status < 500) break;
	\\      } catch {}
	\\      await new Promise((resolve) => setTimeout(resolve, 100));
	\\    }
	\\    location.reload();
	\\  };
	\\  events.addEventListener('hello', (event) => {
	\\    if (build !== null && build !== event.data) reload();
	\\    build = event.data;
	\\  });
	\\  events.addEventListener('reload', reload);
	\\  events.addEventListener('fixed', reload);
	\\  events.addEventListener('failed', (event) => {
	\\    const [name, ...report] = event.data.split(newline);
	\\    console.error('Joy: ' + name + ' failed to build' + newline + report.join(newline));
	\\  });
	\\  events.addEventListener('asset', (event) => {
	\\    const file = '/' + event.data;
	\\    const sheets = [...document.querySelectorAll('link[rel="stylesheet"]')].filter((link) => new URL(link.href).pathname.endsWith(file));
	\\    if (sheets.length > 0) {
	\\      for (const link of sheets) {
	\\        const url = new URL(link.href);
	\\        url.searchParams.set('joy', String(Date.now()));
	\\        link.href = url.href;
	\\      }
	\\    } else if (performance.getEntriesByType('resource').some((entry) => new URL(entry.name).pathname.endsWith(file))) {
	\\      reload();
	\\    }
	\\  });
	\\}

hello : Str, U64 -> Sse.Event
hello = |session, build| Sse.Event.named("hello", ["${session}-${build.to_str()}"])

## Start a built server, with JOY_ASSETS_JSON pointing it at the dev build
## and `env` besides.
start_server! : Str, Str, List((Str, Str)) => Try(Started, _)
start_server! = |root, name, env| {
	process =
		env
			.fold(Cmd.new(OsStr.from_str("${root}/.joy/dev/servers/${name}/main")), |cmd, (key, value)| cmd.env(OsStr.from_str(key), OsStr.from_str(value)))
			.env(OsStr.from_str("JOY_ASSETS_JSON"), OsStr.from_str("${root}/.joy/dev/assets.json"))
			.stdin(Null)
			.stdout(Pipe)
			.stderr(Pipe)
			.pending_limit(16 * 1024 * 1024)
			.spawn_leashed!()?
	Stdout.line!("Started ${name}")?
	Ok({ name, process, pending: "" })
}

## Stop the old server and start the one just built.
restart_server! : DevState, Str => Try(DevState, _)
restart_server! = |state, name| {
	for child in state.children {
		if child.name == name {
			child.process.close!() ?? {}
		}
	}
	started = start_server!(state.root, name, state.server_env)?
	check =
		match state.check {
			Waiting(port) => Pending({ port, since: Monotonic.now!() })
			other => other
		}
	Ok({ ..state, children: state.children.drop_if(|child| child.name == name).append(started), check })
}

## Ask a server that serves its own files for the loader once it answers,
## and say what to do when it answers 404, since its pages then load without
## their bundles. A server that has not answered after 30 seconds is left
## alone.
check_server! : DevState => Try(DevState, _)
check_server! = |state|
	match state.check {
		Pending({ port, since }) => {
			loader = "${state.client_url}joy.js"
			request = Request.from_method(GET).with_uri("http://127.0.0.1:${port.to_str()}${loader}").with_timeout(TimeoutMilliseconds(500))
			match Http.send!(request, {}) {
				Ok(response) => {
					if Response.status(response) == 404 {
						Stderr.line!("The server on ${port.to_str()} answers 404 for ${loader}, so its pages load without their bundles. Serve the files with Names.file from generated/, or set JOY_SERVE_FILES=1 if a proxy or a CDN serves them in production, and ./joy dev serves them as it would.")?
					}
					Ok({ ..state, check: Done })
				}
				Err(_) =>
					if Duration.to_seconds(Monotonic.since(Monotonic.now!(), since)) >= 30 {
						Ok({ ..state, check: Done })
					} else {
						Ok(state)
					}
			}
		}
		_ => Ok(state)
	}

## Whether the switch in the environment variable `name` is on: 1, true, yes
## or on, and 0, false, no, off or empty for off.
switch! : Str => Try(Bool, _)
switch! = |name|
	match Env.var_str!(OsStr.from_str(name)) {
		Ok(value) =>
			if ["1", "true", "yes", "on"].contains(value.trim().with_ascii_lowercased()) {
				Ok(True)
			} else if ["", "0", "false", "no", "off"].contains(value.trim().with_ascii_lowercased()) {
				Ok(False)
			} else {
				Build.fail!("${name} is ${Str.inspect(value)}, and ./joy takes 1 or 0.")
			}
		Err(_) => Ok(False)
	}

## A port that is free now, for the project's server.
free_port! : {} => Try(U16, _)
free_port! = |{}| {
	probe = Server.start!({ host: "127.0.0.1", port: 0 }, |_| Ok(Server.respond(Response.from_status(503))))?
	port = probe.port()
	Server.stop!(probe)
	Ok(port)
}

## Print what a server printed since the last look, each line with its name.
forward_output! : Started => Try(Started, _)
forward_output! = |child| {
	var $pending = child.pending
	var $reading = True
	while $reading {
		match child.process.read!(Duration.zero) {
			Ok(Stdout(bytes)) | Ok(Stderr(bytes)) => {
				lines = "${$pending}${Str.from_utf8_lossy(bytes)}".split_on("\n")
				complete = lines.drop_last(1)
				$pending = lines.last() ?? ""
				for line in complete {
					Stdout.line!("[${child.name}] ${line}")?
				}
			}
			Err(EndOfInput) => {
				if !$pending.is_empty() {
					Stdout.line!("[${child.name}] ${$pending}")?
					$pending = ""
				}
				match child.process.poll!() {
					Ok(Finished(output)) => Stderr.line!("${child.name} exited: ${Str.inspect(output.status)}. ./joy starts it again after the next change it reaches.")?
					_ => {}
				}
				$reading = False
			}
			Err(_) => {
				$reading = False
			}
		}
	}
	Ok({ ..child, pending: $pending })
}

setting! : [Some(Str), None], Str => Try(Str, [Unset])
setting! = |given, variable|
	match given {
		Some(value) => Ok(value)
		None =>
			match Env.var_str!(OsStr.from_str(variable)) {
				Ok(value) if !value.is_empty() => Ok(value)
				_ => Err(Unset)
			}
	}

parse_port! : Str => Try(U16, _)
parse_port! = |text|
	match U16.from_str(text) {
		Ok(port) => Ok(port)
		Err(_) => Build.fail!("A port is a number up to 65535, not ${text}.")
	}

## `PATH=URL`: requests whose path starts with PATH go to the backend at URL.
parse_proxy! : Str => Try((Str, Str), _)
parse_proxy! = |given|
	match given.split_first("=") {
		Ok({ before, after }) if before.starts_with("/") and (after.starts_with("http://") or after.starts_with("https://")) => Ok((before, after))
		_ => Build.fail!("--proxy takes PATH=URL, like /api=http://localhost:3000, not ${given}.")
	}
