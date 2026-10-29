import pf.Cmd
import pf.Crypt
import pf.Duration
import pf.Env
import pf.OsStr
import pf.Path
import pf.Sleep

## Run roc builds, a few at a time, and check each one.
## roc's exit code is not trusted, since it can exit 0 with errors and 2 on
## warnings. The old output is deleted first, the log's summary line must
## report no errors, and the new output must exist, so a stale module never
## reaches a page.
Compile :: [].{
	Job : {
		name : Str,
		file : Str,
		output : Str,
		args : List(Str),
		inputs : Str,

		## The roc cache the build uses, see [cache_root!].
		cache : Str,
		own_warnings_fail : Bool,
	}

	## A finished build: `Built` with the warnings it printed, or `Failed`,
	## and the whole log either way.
	Result : { job : Job, outcome : [Built, Failed], log : Str, warnings : List(Str) }

	Running : { job : Job, child : Cmd.Child }

	State : { queue : List(Job), running : List(Running), done : List(Result) }

	## Delete the old output and start roc. The child dies with ./joy.
	start! : Job => Try(Running, _)
	start! = |job| {
		_ = Path.utf8(job.output).delete!()
		match job.output.split_last("/") {
			Ok({ before, .. }) => Path.utf8(before).create_all!()?
			Err(_) => {}
		}
		inputs = if (job.inputs.is_empty()) [] else ["--watch-inputs-file=${job.inputs}"]
		args = job.args.concat(inputs).concat(["--output=${job.output}", job.file])
		child =
			Cmd.new(OsStr.from_str("roc"))
				.args(args.map(OsStr.from_str))
				# WORKAROUND: a cache per server and one for the bundles, for each
				# set of --replace-dep flags, see cache_root!.
				.env(OsStr.from_str("ROC_CACHE_DIR"), OsStr.from_str(job.cache))
				.stdin(Null)
				.stdout(Capture)
				.stderr(MergeWithStdout)
				.output_limit(MaxBytes(256 * 1024 * 1024))
				.spawn_leashed!()?
		Ok({ job, child })
	}

	## WORKAROUND: the folder that holds the roc caches of the builds whose
	## arguments are `args`. Every server gets a cache of its own and the
	## bundles share one, all apart from roc's default cache, so neither a
	## server's build nor an editor's `roc check` of a server writes into the
	## cache a bundle's build reads. On roc 0c440e5 a check or build of one
	## program caches results that name a module only that program has, and
	## the next build of another program that shares a package with it
	## segfaults in post-check monotype when it reads them:
	## https://github.com/roc-lang/roc/issues/12693 and
	## https://github.com/roc-lang/roc/issues/12701. A build with other
	## `--replace-dep` flags is another program too: `./joy build` swaps
	## generated/ for the build's hashed copy and `./joy dev` does not, and a
	## server built one way crashes when it is built the other way in the
	## same cache. So each set of `--replace-dep` flags gets caches of its
	## own, in a folder named after their hash. Bundles sharing a cache have
	## not shown it. The caches live below `ROC_CACHE_DIR` when it is set,
	## else in .joy/roc-cache. Remove this once both issues are fixed.
	cache_root! : List(Str) => Try(Str, _)
	cache_root! = |args| {
		base =
			match Env.var_str!(OsStr.from_str("ROC_CACHE_DIR")) {
				Ok(dir) if !dir.is_empty() => "${dir}/joy"
				_ => "${Path.display(Env.cwd!()?)}/.joy/roc-cache"
			}
		replaced = replace_deps(args)
		if replaced.is_empty() {
			Ok("${base}/plain")
		} else {
			digest = Crypt.hash!(Str.to_utf8(Str.join_with(replaced, " ")), Sha256)
			Ok("${base}/${Str.from_utf8(Str.to_utf8(digest).take_first(8)) ?? digest}")
		}
	}

	## The roc cache of the server `name`, see [cache_root!].
	server_cache : Str, Str -> Str
	server_cache = |root, name| "${root}/servers/${name}"

	## The roc cache the bundles share, see [cache_root!].
	bundle_cache : Str -> Str
	bundle_cache = |root| "${root}/bundles"

	## Collect the builds that finished, then start queued ones until `jobs`
	## run. Returns at once.
	step! : State, U64 => Try(State, _)
	step! = |state, jobs| {
		var $running = []
		var $done = state.done
		for running in state.running {
			match running.child.poll!() {
				Ok(Running) => {
					$running = $running.append(running)
				}
				Ok(Finished(output)) => {
					$done = $done.append(finish!(running.job, Str.from_utf8_lossy(output.stdout_bytes)))
				}
				Err(err) => {
					$done = $done.append({ job: running.job, outcome: Failed, log: "roc did not run: ${Str.inspect(err)}", warnings: [] })
				}
			}
		}
		var $queue = state.queue
		while $running.len() < jobs and !$queue.is_empty() {
			match $queue {
				[job, .. as rest] => {
					$queue = rest
					match start!(job) {
						Ok(started) => {
							$running = $running.append(started)
						}
						Err(err) => {
							$done = $done.append({ job, outcome: Failed, log: "roc did not start: ${Str.inspect(err)}", warnings: [] })
						}
					}
				}
				[] => {}
			}
		}
		Ok({ queue: $queue, running: $running, done: $done })
	}

	## Run every job, `jobs` at a time, and wait for all of them. `finished!`
	## hears about each build as it ends.
	run_all! : List(Job), U64, (Compile.Result => Try({}, _)) => Try(List(Compile.Result), _)
	run_all! = |all, jobs, finished!| {
		var $state = { queue: all, running: [], done: [] }
		var $reported = 0
		while !$state.queue.is_empty() or !$state.running.is_empty() {
			$state = step!($state, jobs)?
			for result in $state.done.drop_first($reported) {
				finished!(result)?
			}
			$reported = $state.done.len()
			if !$state.running.is_empty() {
				Sleep.millis!(20)?
			}
		}
		Ok($state.done)
	}

	## The summary line's counts, the last one in the log.
	summary : Str -> [Some({ errors : U64, warnings : U64 }), None]
	summary = |log|
		match strip_ansi(log).split_on("\n").keep_oks(counts_of).last() {
			Ok(counts) => Some(counts)
			Err(_) => None
		}

	## The files of the warnings a log reports, as roc names them.
	warning_files : Str -> List(Str)
	warning_files = |log|
		strip_ansi(log)
			.split_on("\n")
			.keep_if(|line| line.starts_with("── ●") or line.starts_with("-- ●"))
			.keep_oks(location_file)

	## Whether roc names a file of this project: a path inside it, not one
	## that leads out of it or into roc's package cache.
	is_own : Str -> Bool
	is_own = |file| !file.starts_with("/") and !file.starts_with("..") and !file.contains(":\\")
}

finish! : Compile.Job, Str => Compile.Result
finish! = |job, log| {
	exists = Path.utf8(job.output).is_file!() ?? False
	warnings = Compile.warning_files(log)
	clean =
		match Compile.summary(log) {
			Some({ errors, .. }) => errors == 0
			None => False
		}
	own_warnings = warnings.keep_if(Compile.is_own)
	outcome = if (clean and exists and !(job.own_warnings_fail and !own_warnings.is_empty())) Built else Failed
	if outcome == Failed {
		# Only a clean build may leave its output behind.
		_ = Path.utf8(job.output).delete!()
		{}
	}
	{ job, outcome, log, warnings }
}

## `N error(s) and M warning(s)` anywhere in a line.
counts_of : Str -> Try({ errors : U64, warnings : U64 }, [NoCounts])
counts_of = |line| find_counts(line.split_on(" ").drop_if(|word| word.is_empty()))

find_counts : List(Str) -> Try({ errors : U64, warnings : U64 }, [NoCounts])
find_counts = |words|
	match words {
		[errors, error_word, "and", warnings, warning_word, ..] if (error_word == "error" or error_word == "errors") and (warning_word.starts_with("warning")) =>
			match (U64.from_str(errors), U64.from_str(warnings)) {
				(Ok(e), Ok(w)) => Ok({ errors: e, warnings: w })
				_ => Err(NoCounts)
			}

		[_, .. as rest] => find_counts(rest)
		[] => Err(NoCounts)
	}

## The file of a report heading that ends in `path:line:col`.
location_file : Str -> Try(Str, [NoLocation])
location_file = |line|
	match line.split_on(" ").drop_if(|word| word.is_empty()).last() {
		Ok(location) =>
			match location.split_first(":") {
				Ok({ before, .. }) if !before.is_empty() => Ok(before)
				_ => Err(NoLocation)
			}

		Err(_) => Err(NoLocation)
	}

strip_ansi : Str -> Str
strip_ansi = |text|
	if text.contains("\u(1b)[") {
		Str.from_utf8_lossy(strip_ansi_bytes(Str.to_utf8(text), [], Plain))
	} else {
		text
	}

strip_ansi_bytes : List(U8), List(U8), [Plain, Escape, Sequence] -> List(U8)
strip_ansi_bytes = |bytes, kept, mode|
	match bytes {
		[] => kept
		[byte, .. as rest] =>
			match mode {
				Plain => if (byte == 0x1b) strip_ansi_bytes(rest, kept, Escape) else strip_ansi_bytes(rest, kept.append(byte), Plain)
				Escape => if (byte == '[') strip_ansi_bytes(rest, kept, Sequence) else strip_ansi_bytes(rest, kept, Plain)
				Sequence => if (byte >= 0x40 and byte <= 0x7e) strip_ansi_bytes(rest, kept, Plain) else strip_ansi_bytes(rest, kept, Sequence)
			}
	}

## The OLD and NEW of every `--replace-dep OLD NEW` in a roc command line.
replace_deps : List(Str) -> List(Str)
replace_deps = |args|
	match args {
		["--replace-dep", old, new, .. as rest] => [old, new].concat(replace_deps(rest))
		[_, .. as rest] => replace_deps(rest)
		[] => []
	}

expect replace_deps(["build", "--replace-dep", "a", "b", "--opt=dev", "--replace-dep", "c", "d"]) == ["a", "b", "c", "d"]
expect replace_deps(["build", "--opt=dev"]) == []
