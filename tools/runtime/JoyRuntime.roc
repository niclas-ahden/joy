## Build an app's runtime.js: Joy's core plus the browser-feature code of
## exactly the platform functions the app calls.
##
## Every effect has an id (`joy/media/record`), which the function that
## issues it writes as a string literal. The platform's id types take nothing
## else, and mark each one: `<joy-effect joy/media/record>` (see Effect.Id and
## Sub.Id). The Roc compiler drops the functions an app never calls, and their
## literals with them, so the marked ids in the app's compiled wasm are the
## effects it uses. `generate` finds them in the wasm's data section and
## appends those effects, and the helpers they need, to the core.
##
## The functions are pure: the caller reads the files and writes the result.
##
## ```
## runtime = JoyRuntime.generate({ core, features: [media_js], wasm })?
## ```
##
## That is for a release build. During development `full` holds every
## feature instead, so the runtime.js never has to keep up with the wasm.
JoyRuntime := [].{
	## A part of a feature file (www/features/<feature>.js), from one `////`
	## line to the next: the JavaScript of an Effect.call or Effect.send
	## (`effect <id>`), of a Sub.listen (`subscription <id>`) or a
	## `helper <name>`, with the helpers it needs (`needs <name> ...`).
	Section : {
		kind : [Effect, Subscription, Helper],
		name : Str,
		needs : List(Str),
		code : Str,
	}

	## The sections of a feature file, in order. Code before the first `////`
	## line is shared by every effect and subscription of the file, as a
	## helper each of them needs. Comments there belong to none.
	sections : Str -> Try(List(JoyRuntime.Section), [BadSection(Str)])
	sections = |source| {
		parts = "\n${source}".split_on("\n//// ")
		top = (parts.first() ?? "").trim_start()
		is_code = top.split_on("\n").any(|line| !line.trim().is_empty() and !line.trim().starts_with("//"))
		shared = if (is_code) [{ kind: Helper, name: top_of_file, needs: [], code: "${top.trim_end()}\n" }] else []
		written = parts
			.drop_first(1)
			.map_try(
				|part| {
					(header, code) =
						match part.split_first("\n") {
							Ok({ before, after }) => (before, after)
							Err(_) => (part, "")
						}
					words = header.split_on(" ").drop_if(|w| w.is_empty())
					(kind, name, rest) =
						match words {
							["effect", id, .. as more] => (Effect, id, more)
							["subscription", id, .. as more] => (Subscription, id, more)
							["helper", helper, .. as more] => (Helper, helper, more)
							_ => return Err(BadSection(header))
						}
					named =
						match rest {
							[] => []
							["needs", .. as names] => names
							_ => return Err(BadSection(header))
						}
					needs = if (is_code and kind != Helper) named.append(top_of_file) else named
					Ok({ kind, name, needs, code: "//// ${header}\n${code}" })
				},
			)?
		Ok(shared.concat(written))
	}

	## The bytes of a wasm module's data segments, where its long string
	## literals live.
	data_bytes : List(U8) -> Try(List(U8), [NotWasm, BadWasm(Str)])
	data_bytes = |wasm|
		if wasm.take_first(4) != [0, 97, 115, 109] {
			Err(NotWasm)
		} else {
			data_sections(wasm, 8, [])
		}

	## The ids in a wasm module's data, each with what it is the id of, as the
	## platform marks them.
	ids_in : List(U8) -> Try(List({ id : Str, kind : [Effect, Subscription] }), [NotWasm, BadWasm(Str)])
	ids_in = |wasm| {
		data = JoyRuntime.data_bytes(wasm)?
		Ok(marked(data, "<joy-effect ", Effect).concat(marked(data, "<joy-listen ", Subscription)))
	}

	## The ids among `ids` whose plain text is in a wasm module's data, marked
	## or not. An id that is there without one mark in the whole module was
	## not put there the way `ids_in` reads it.
	texts_in : List(U8), List(Str) -> Try(List(Str), [NotWasm, BadWasm(Str)])
	texts_in = |wasm, ids| {
		data = Str.from_utf8_lossy(JoyRuntime.data_bytes(wasm)?)
		Ok(ids.keep_if(|id| data.contains(id)))
	}

	## The ids among `ids` that a wasm module uses.
	used_ids : List(U8), List(Str) -> Try(List(Str), [NotWasm, BadWasm(Str)])
	used_ids = |wasm, ids| {
		found = JoyRuntime.ids_in(wasm)?
		Ok(ids.keep_if(|id| found.any(|one| one.id == id)))
	}

	## What a shipped app gets of a runtime: the code as written, without comments
	## or indentation. Joy's own JavaScript holds no string across lines, so this can
	## go by lines.
	shipping : Str -> Str
	shipping = |js| {
		lines = js.split_on("\n").map(|line| line.trim()).drop_if(|code| code.is_empty() or code.starts_with("//"))
		Str.join_with(lines, "\n")
	}

	## The runtime.js ./joy dev serves: `runtime` (see `full`) with hot reloading's
	## additions from `seams` (the source of www/hot-seams.js), each section at the
	## comment of its name, and the `module` section at the end.
	hot : { runtime : Str, seams : Str } -> Try(Str, [NoSeam(Str)])
	hot = |{ runtime, seams }| {
		section = |name| {
			parts = "\n${seams}".split_on("\n//// ")
			match parts.keep_if(|part| part.starts_with("${name}\n")).first() {
				Ok(part) => Ok(part.drop_prefix("${name}\n"))
				Err(_) => Err(NoSeam(name))
			}
		}
		for name in ["runtime", "mount"] {
			if !runtime.contains("// hot:${name}") {
				return Err(NoSeam(name))
			}
		}
		in_runtime = section("runtime")?
		in_mount = section("mount")?
		at_end = section("module")?
		Ok("${runtime.replace_first("// hot:runtime", in_runtime).replace_first("// hot:mount", in_mount)}\n${at_end}")
	}

	## The runtime.js for an app's release build: `core`, then for each
	## feature in `features` (the sources of www/features/*.js) the
	## effects whose ids `wasm` contains and the helpers those need, each
	## feature in a block of its own so its names stay its own.
	generate : { core : Str, features : List(Str), wasm : List(U8) } -> Try(Str, [BadSection(Str), NotWasm, BadWasm(Str), MissingHelper(Str)])
	generate = |{ core, features, wasm }| {
		parsed = features.map_try(JoyRuntime.sections)?
		used = JoyRuntime.used_ids(wasm, effect_ids(parsed))?
		header = "\n// Features this app uses (see tools/runtime): ${if used.is_empty() "none" else Str.join_with(used, ", ")}\n"
		Ok(JoyRuntime.shipping(assemble(core, "\n", parsed, used)?).concat(header))
	}

	## The runtime.js for development: `core` and every feature, whatever
	## the app calls. The wasm changes on nearly every edit, and a runtime.js
	## made from it would have to be made again in step with it, so a watch
	## loop serves this one and leaves `generate` to the release build.
	full : { core : Str, features : List(Str) } -> Try(Str, [BadSection(Str), MissingHelper(Str)])
	full = |{ core, features }| {
		parsed = features.map_try(JoyRuntime.sections)?
		Ok(assemble(core, "\n// Every feature, for development (see tools/runtime)\n", parsed, effect_ids(parsed))?)
	}

	## The runtime.js for several apps that load it together, the bundles of
	## one build that share one joy.js: `core` and the effects any of
	## `wasms` uses. `features` are Joy's own, which ship without comments
	## and indentation (see `shipping`). `custom` are the files a project and
	## its packages bring, which ship as they are written: nothing is known of
	## how their lines may be taken apart.
	##
	## The two come back apart: `runtime` is Joy's, and `custom` is a module
	## of its own (see `custom_module`), empty when the apps use none of it.
	generate_all : { core : Str, features : List(Str), custom : List(Str), wasms : List(List(U8)) } -> Try({ runtime : Str, custom : Str }, [BadSection(Str), NotWasm, BadWasm(Str), MissingHelper(Str)])
	generate_all = |{ core, features, custom, wasms }| {
		parsed = features.map_try(JoyRuntime.sections)?
		brought = custom.map_try(JoyRuntime.sections)?
		ids = effect_ids(parsed.concat(brought))
		per_wasm = wasms.map_try(|wasm| JoyRuntime.used_ids(wasm, ids))?
		used = ids.keep_if(|id| per_wasm.any(|found| found.contains(id)))
		header = "\n// Features these apps use (see tools/runtime): ${if used.is_empty() "none" else Str.join_with(used, ", ")}\n"
		Ok({ runtime: JoyRuntime.shipping(assemble(core, "\n", parsed, used)?).concat(header), custom: JoyRuntime.custom_module(custom, Used(used))? })
	}

	## The module of the JavaScript a project and its packages bring: each
	## file's code for the ids in question, in a block of its own, inside a
	## function that is handed what such code may use. It is not part of
	## runtime.js, so nothing else of the runtime is in its reach. Empty when
	## no file has code for the ids.
	custom_module : List(Str), [Every, Used(List(Str))] -> Try(Str, [BadSection(Str), MissingHelper(Str)])
	custom_module = |custom, which| {
		parsed = custom.map_try(JoyRuntime.sections)?
		used =
			match which {
				Every => effect_ids(parsed)
				Used(ids) => ids
			}
		blocks = parsed.map_try(|feature_sections| feature_block(feature_sections, used))?.keep_if(|block| !block.is_empty())
		if blocks.is_empty() {
			Ok("")
		} else {
			Ok("// The custom effects of this app and its packages (see Custom effects in Joy's guide).\nexport default ({ defineEffect, defineSubscription, WireWriter }) => {\n${Str.join_with(blocks, "")}};\n")
		}
	}

	## `runtime` with the line that loads the module of custom effects by
	## the name it has beside it.
	with_custom : Str, Str -> Str
	with_custom = |runtime, name| "${runtime}\nloadCustomEffects(() => import('./${name}'));\n"
}

## The name of the helper that is a file's code before its first section.
top_of_file : Str
top_of_file = "(top of file)"

## The ids of every effect and subscription in the parsed features.
effect_ids : List(List(JoyRuntime.Section)) -> List(Str)
effect_ids = |parsed| parsed.join().keep_if(|s| s.kind != Helper).map(|s| s.name)

## `core`, `header`, then each feature's code for the used ids, in a block
## of its own.
assemble : Str, Str, List(List(JoyRuntime.Section)), List(Str) -> Try(Str, [MissingHelper(Str)])
assemble = |core, header, parsed, used| {
	blocks = parsed.map_try(|feature_sections| feature_block(feature_sections, used))?
	included = blocks.keep_if(|b| !b.is_empty())
	Ok(Str.join_with([core, header].concat(included), ""))
}

## One feature's code for the used ids: their sections and every helper
## they need, transitively, in the order the file has them. Empty when the
## app uses none of the feature's effects.
feature_block : List(JoyRuntime.Section), List(Str) -> Try(Str, [MissingHelper(Str)])
feature_block = |sections, used| {
	roots = sections.keep_if(|s| s.kind != Helper and used.contains(s.name))
	if roots.is_empty() {
		Ok("")
	} else {
		needed = helpers_needed(sections, roots.map(|s| s.needs).join(), [])?
		chosen = sections.keep_if(|s| if s.kind == Helper needed.contains(s.name) else used.contains(s.name))
		Ok("{\n${Str.join_with(chosen.map(|s| s.code), "")}}\n")
	}
}

## The helpers in `wanted` and the ones they need in turn.
helpers_needed : List(JoyRuntime.Section), List(Str), List(Str) -> Try(List(Str), [MissingHelper(Str)])
helpers_needed = |sections, wanted, found|
	match wanted {
		[] => Ok(found)
		[name, .. as rest] =>
			if found.contains(name) {
				helpers_needed(sections, rest, found)
			} else {
				helper = sections.find_first(|s| s.kind == Helper and s.name == name) ? |_| MissingHelper(name)
				helpers_needed(sections, rest.concat(helper.needs), found.append(name))
			}
	}

## Walk the module's sections from `at`, collecting the data section's
## segments. A section is an id byte and a LEB128 size, then its content.
data_sections : List(U8), U64, List(U8) -> Try(List(U8), [BadWasm(Str)])
data_sections = |wasm, at, acc|
	if at >= wasm.len() {
		Ok(acc)
	} else {
		section_id = wasm.get(at) ? |_| BadWasm("section id")
		(size, content_at) = leb(wasm, at + 1)?
		next = content_at + size.to_u64()
		if section_id == 11 {
			(count, segments_at) = leb(wasm, content_at)?
			data_sections(wasm, next, acc.concat(segments(wasm, segments_at, count, [])?))
		} else {
			data_sections(wasm, next, acc)
		}
	}

## `count` data segments from `at`: active ones (flags 0, or 2 with a memory
## index) have an offset expression before their bytes, passive ones (1) do
## not.
segments : List(U8), U64, U32, List(U8) -> Try(List(U8), [BadWasm(Str)])
segments = |wasm, at, count, acc|
	if count == 0 {
		Ok(acc)
	} else {
		(flags, after_flags) = leb(wasm, at)?
		bytes_at =
			match flags {
				0 => skip_expr(wasm, after_flags)?
				1 => after_flags
				2 => {
					(_, after_memory) = leb(wasm, after_flags)?
					skip_expr(wasm, after_memory)?
				}
				_ => return Err(BadWasm("data segment flags"))
			}
		(len, content_at) = leb(wasm, bytes_at)?
		segments(wasm, content_at + len.to_u64(), count - 1, acc.concat(wasm.sublist({ start: content_at, len: len.to_u64() })))
	}

## Past a constant expression: instructions with LEB128 immediates (an
## i32 or i64 constant, a global) up to `end` (0x0b).
skip_expr : List(U8), U64 -> Try(U64, [BadWasm(Str)])
skip_expr = |wasm, at| {
	opcode = wasm.get(at) ? |_| BadWasm("expression")
	if opcode == 0x0b {
		Ok(at + 1)
	} else if opcode == 0x41 or opcode == 0x42 or opcode == 0x23 {
		skip_expr(wasm, skip_leb(wasm, at + 1)?)
	} else {
		Err(BadWasm("unexpected instruction ${opcode.to_str()} in a data offset"))
	}
}

## An unsigned LEB128 number at `at`, and where the bytes after it start.
leb : List(U8), U64 -> Try((U32, U64), [BadWasm(Str)])
leb = |bytes, at| leb_from(bytes, at, 0, 0)

leb_from : List(U8), U64, U32, U8 -> Try((U32, U64), [BadWasm(Str)])
leb_from = |bytes, at, value, shift| {
	byte = bytes.get(at) ? |_| BadWasm("number")
	if shift > 28 {
		Err(BadWasm("number too long"))
	} else {
		next = value.bitwise_or((byte.bitwise_and(0x7f)).to_u32().shl_wrap(shift))
		if byte.bitwise_and(0x80) == 0 Ok((next, at + 1)) else leb_from(bytes, at + 1, next, shift + 7)
	}
}

## Past an LEB128 number of any length (signed constants included).
skip_leb : List(U8), U64 -> Try(U64, [BadWasm(Str)])
skip_leb = |bytes, at| {
	byte = bytes.get(at) ? |_| BadWasm("number")
	if byte.bitwise_and(0x80) == 0 Ok(at + 1) else skip_leb(bytes, at + 1)
}

## The ids in `data` after each `mark` and up to the `>` that ends it. What
## stands there without being an id, by its letters, is something else's bytes.
marked : List(U8), Str, [Effect, Subscription] -> List({ id : Str, kind : [Effect, Subscription] })
marked = |data, mark, kind| {
	needle = mark.to_utf8()
	var $found = []
	var $at = 0
	while $at + needle.len() < data.len() {
		if data.get($at) == Ok('<') and data.sublist({ start: $at, len: needle.len() }) == needle {
			after = Str.from_utf8_lossy(data.sublist({ start: $at + needle.len(), len: longest_id + 1 }))
			match after.split_first(">") {
				Ok({ before, .. }) if !before.is_empty() and Str.to_utf8(before).all(in_an_id) and !$found.any(|one| one.id == before) => {
					$found = $found.append({ id: before, kind })
				}
				_ => {}
			}
		}
		$at = $at + 1
	}
	$found
}

## More bytes than an id is read for.
longest_id : U64
longest_id = 200

## Whether a byte can be part of an id, as Effect.Id and Sub.Id have it.
in_an_id : U8 -> Bool
in_an_id = |byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_' or byte == '-' or byte == '.' or byte == '/'

feature_source : Str
feature_source =
	\\// a test feature
	\\
	\\//// helper shared
	\\const shared = 1;
	\\
	\\//// effect joy/test/first needs shared
	\\defineEffect('joy/test/first', () => shared);
	\\
	\\//// effect joy/test/second
	\\defineEffect('joy/test/second', () => 2);
	\\

## A wasm module with one active data segment holding `text`.
wasm_with : Str -> List(U8)
wasm_with = |text| {
	bytes = text.to_utf8()
	len = bytes.len().to_u8_try() ?? 0
	segment = [1, 0, 0x41, 0, 0x0b, len].concat(bytes)
	section_len = segment.len().to_u8_try() ?? 0
	[0, 97, 115, 109, 1, 0, 0, 0, 11, section_len].concat(segment)
}

expect JoyRuntime.shipping("// about\n  keep();\n\n  // hot:mount\n  more();") == "keep();\nmore();"

expect JoyRuntime.hot({ runtime: "a();\n// hot:runtime\nb();\n// hot:mount\nc();", seams: "// about\n//// runtime\nr();\n//// mount\nm();\n//// module\ne();\n" }) == Ok("a();\nr();\nb();\nm();\nc();\ne();\n")
expect JoyRuntime.hot({ runtime: "a();", seams: "//// runtime\nr();\n" }) == Err(NoSeam("runtime"))

expect JoyRuntime.sections(feature_source).map_ok(|s| s.map(|x| x.name)) == Ok(["shared", "joy/test/first", "joy/test/second"])
expect JoyRuntime.sections("//// effect a/b\nx").map_ok(|s| s.map(|x| x.name)) == Ok(["a/b"])
expect JoyRuntime.used_ids(wasm_with("..<joy-effect joy/test/first>.."), ["joy/test/first", "joy/test/second"]) == Ok(["joy/test/first"])
# An id without its mark is some other text, and so is a mark without an id.
expect JoyRuntime.used_ids(wasm_with("joy/test/first <joy-effect ><joy-effect a b>"), ["joy/test/first"]) == Ok([])
expect JoyRuntime.ids_in(wasm_with("<joy-listen a/keys>x<joy-effect a/b><joy-effect a/b>")) == Ok([{ id: "a/b", kind: Effect }, { id: "a/keys", kind: Subscription }])
expect JoyRuntime.data_bytes([1, 2, 3, 4]) == Err(NotWasm)
expect JoyRuntime.custom_module(["//// effect my/unused\ndefineEffect('my/unused', () => 0);\n"], Used(["my/other"])) == Ok("")
expect JoyRuntime.custom_module(["//// effect my/one\none();\n"], Every).map_ok(|js| js.contains("{\n//// effect my/one\none();\n}\n")) == Ok(Bool.True)
expect JoyRuntime.with_custom("core();", "effects.abc.js") == "core();\nloadCustomEffects(() => import('./effects.abc.js'));\n"
expect JoyRuntime.texts_in(wasm_with("x joy/test/first y"), ["joy/test/first", "joy/test/second"]) == Ok(["joy/test/first"])

# Code at the top of a file is there for each of its sections, and comments are not code.
expect JoyRuntime.sections("// about\n\n//// effect a/b\nx").map_ok(|s| s.map(|x| (x.name, x.needs))) == Ok([("a/b", [])])
expect JoyRuntime.sections("// about\nconst shared = 1;\n\n//// helper more\ny\n//// effect a/b needs more\nx").map_ok(|s| s.map(|x| (x.name, x.needs))) == Ok([("(top of file)", []), ("more", []), ("a/b", ["more", "(top of file)"])])

# What a project brings ships as written, where Joy's own loses its comments and indentation.
expect {
	theirs = "const greeting = `\n  // kept\n  hello`;\n//// effect my/hello\ndefineEffect('my/hello', () => greeting);\n//// effect my/unused\ndefineEffect('my/unused', () => 0);\n"
	generated = JoyRuntime.generate_all({ core: "  // core\n  run();\n", features: [feature_source], custom: [theirs], wasms: [wasm_with("<joy-effect my/hello>")] })
	match generated {
		Ok({ runtime, custom }) =>
			runtime.starts_with("run();\n")
			and !runtime.contains("my/hello'")
			and !runtime.contains("'joy/test/first'")
			and custom.starts_with("// The custom effects of this app and its packages (see Custom effects in Joy's guide).\nexport default ({ defineEffect, defineSubscription, WireWriter }) => {\n{\n")
			and custom.contains("const greeting = `\n  // kept\n  hello`;")
			and custom.contains("'my/hello'")
			and !custom.contains("'my/unused'")
			and custom.ends_with("}\n};\n")

		Err(_) => Bool.False
	}
}

expect {
	generated = JoyRuntime.generate({ core: "// core\n", features: [feature_source], wasm: wasm_with("<joy-effect joy/test/first>") })
	match generated {
		Ok(js) => js.contains("const shared = 1;") and js.contains("'joy/test/first'") and !js.contains("'joy/test/second'")
		Err(_) => Bool.False
	}
}

expect {
	generated = JoyRuntime.generate({ core: "// core\n", features: [feature_source], wasm: wasm_with("nothing here") })
	match generated {
		Ok(js) => !js.contains("const shared") and js.contains("(see tools/runtime): none")
		Err(_) => Bool.False
	}
}

expect {
	generated = JoyRuntime.full({ core: "// core\n", features: [feature_source] })
	match generated {
		Ok(js) => js.contains("const shared = 1;") and js.contains("'joy/test/first'") and js.contains("'joy/test/second'")
		Err(_) => Bool.False
	}
}
