import pf.Cmd
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
				.stdin(Null)
				.stdout(Capture)
				.stderr(MergeWithStdout)
				.output_limit(MaxBytes(256 * 1024 * 1024))
				.spawn_leashed!()?
		Ok({ job, child })
	}

	## How many builds run at once: all of them, or at most what --jobs says.
	Limit : [All, AtMost(U64)]

	## Whether another build may start beside `running` others.
	has_room : Limit, U64 -> Bool
	has_room = |limit, running|
		match limit {
			All => True
			AtMost(jobs) => running < jobs
		}

	## The end of the line that announces the builds, nothing without a limit.
	at_a_time : Limit -> Str
	at_a_time = |limit|
		match limit {
			All => ""
			AtMost(jobs) => ", ${jobs.to_str()} at a time"
		}

	## Collect the builds that finished, then start queued ones while `limit`
	## has room. Returns at once.
	step! : State, Limit => Try(State, _)
	step! = |state, limit| {
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
		while has_room(limit, $running.len()) and !$queue.is_empty() {
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

	## Run every job, within `limit`, and wait for all of them. `finished!`
	## hears about each build as it ends.
	run_all! : List(Job), Limit, (Compile.Result, U64 => Try({}, _)) => Try(List(Compile.Result), _)
	run_all! = |all, limit, finished!| {
		var $state = { queue: all, running: [], done: [] }
		var $reported = 0
		while !$state.queue.is_empty() or !$state.running.is_empty() {
			$state = step!($state, limit)?
			for result in $state.done.drop_first($reported) {
				$reported = $reported + 1
				finished!(result, $reported)?
			}
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

	## What ./joy adds below a report of roc's that leaves out the way on:
	## a module that is not in its package's list, and an id of a custom
	## effect that is not a string literal. `header` is the text of `file`,
	## the app that was built, which says where its packages are.
	hints : Str, Str, Str -> Str
	hints = |log, header, file| {
		plain = strip_ansi(log).replace_each("\n", " ")
		unlisted =
			match plain.split_first("The package import `") {
				Ok({ after, .. }) =>
					match (after.split_first("`"), plain.contains("does not name a public module")) {
						(Ok({ before, .. }), True) =>
							match before.split_first(".") {
								Ok({ before: shorthand, after: wanted }) => {
									folder =
										match file.split_last("/") {
											Ok(parts) => "${parts.before}/"
											Err(_) => ""
										}
									list =
										match header.split_first("${shorthand}: \"") {
											Ok(parts) => "${folder}${parts.after.split_on("\"").first() ?? "its main.roc"}"
											Err(_) => "the package's main.roc"
										}
									[
										"Hint from ./joy: ${wanted} is not in the list of the modules of the package ${shorthand}.",
										"Add it to the list at the top of ${list}:",
										"",
										"    package [..., ${wanted}] {",
									]
								}
								Err(_) => []
							}
						_ => []
					}
				Err(_) => []
			}
		ids =
			if plain.contains("Effect.Id") or plain.contains("Sub.Id") {
				[
					"Hint from ./joy: Effect.Id and Sub.Id are the ids of effects. An id is written",
					"as a string, \"my_app/share_link\", right where it is used or as a value with",
					"one of those types. One put together while the app runs cannot be an id,",
					"as a build reads the ids an app uses out of what roc compiled.",
				]
			} else {
				[]
			}
		found = if (unlisted.is_empty() or ids.is_empty()) unlisted.concat(ids) else unlisted.concat([""]).concat(ids)
		if (found.is_empty()) "" else "\n${Str.join_with(found, "\n")}\n"
	}
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
	{ job, outcome, log: if (outcome == Failed) Str.concat(log, Compile.hints(log, Path.utf8(job.file).read_utf8!() ?? "", job.file)) else log, warnings }
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

expect Compile.has_room(All, 1000)
expect Compile.has_room(AtMost(2), 1)
expect !Compile.has_room(AtMost(2), 2)
expect Compile.at_a_time(All) == ""
expect Compile.at_a_time(AtMost(3)) == ", 3 at a time"

expect Compile.hints("0 errors and 0 warnings found", "", "client/main.roc") == ""
expect {
	log = "── ✗ package module is private ──\n\nThe package import `effects.Network` does not name a public module declared by\nthat package.\n"
	header = "app [Model] {\n\tpf: platform \"x\",\n\teffects: \"effects/main.roc\",\n}\n"
	Compile.hints(log, header, "client/main.roc")
		== "\nHint from ./joy: Network is not in the list of the modules of the package effects.\nAdd it to the list at the top of client/effects/main.roc:\n\n    package [..., Network] {\n"
}
expect Compile.hints("But the function needs the first argument to be:\n\n    Effect.Id\n", "", "client/main.roc").starts_with("\nHint from ./joy: Effect.Id and Sub.Id are the ids of effects.")
