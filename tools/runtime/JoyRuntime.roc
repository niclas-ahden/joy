## Build an app's runtime.js: Joy's core plus the browser-feature code of
## exactly the platform functions the app calls.
##
## Every feature operation has an id of at least 12 bytes (`joy/media/record`),
## which the platform function that issues it passes as a string literal. The
## Roc compiler drops the functions an app never calls, and their literals
## with them, so the ids in the app's compiled wasm are the operations it
## uses. `generate` finds them in the wasm's data section and appends those
## operations, and the helpers they need, to the core. A shorter string would
## be packed into the code instead of the data, where it cannot be found, so
## a shorter id is refused.
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
	## line to the next: an operation for Effect.call (`op <id>`), an event
	## source for Sub.listen (`events <id>`) or a `helper <name>`, with the
	## helpers it needs (`needs <name> ...`).
	Section : {
		kind : [Operation, Events, Helper],
		name : Str,
		needs : List(Str),
		code : Str,
	}

	## The sections of a feature file, in order. What comes before the first
	## `////` line (the file's own comments) belongs to none.
	sections : Str -> Try(List(JoyRuntime.Section), [BadSection(Str), ShortId(Str)])
	sections = |source|
		"\n${source}"
			.split_on("\n//// ")
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
							["op", id, .. as more] => (Operation, id, more)
							["events", id, .. as more] => (Events, id, more)
							["helper", helper, .. as more] => (Helper, helper, more)
							_ => return Err(BadSection(header))
						}
					needs =
						match rest {
							[] => []
							["needs", .. as names] => names
							_ => return Err(BadSection(header))
						}
					if kind != Helper and name.count_utf8_bytes() < 12 {
						Err(ShortId(name))
					} else {
						Ok({ kind, name, needs, code: "//// ${header}\n${code}" })
					}
				},
			)

	## The bytes of a wasm module's data segments, where its long string
	## literals live.
	data_bytes : List(U8) -> Try(List(U8), [NotWasm, BadWasm(Str)])
	data_bytes = |wasm|
		if wasm.take_first(4) != [0, 97, 115, 109] {
			Err(NotWasm)
		} else {
			data_sections(wasm, 8, [])
		}

	## The ids among `ids` that appear in a wasm module's data.
	used_ids : List(U8), List(Str) -> Try(List(Str), [NotWasm, BadWasm(Str)])
	used_ids = |wasm, ids| {
		data = JoyRuntime.data_bytes(wasm)?
		Ok(ids.keep_if(|id| contains(data, id.to_utf8())))
	}

	## The runtime.js for an app's release build: `core`, then for each
	## feature in `features` (the sources of www/features/*.js) the
	## operations whose ids `wasm` contains and the helpers those need, each
	## feature in a block of its own so its names stay its own.
	generate : { core : Str, features : List(Str), wasm : List(U8) } -> Try(Str, [BadSection(Str), ShortId(Str), NotWasm, BadWasm(Str), MissingHelper(Str)])
	generate = |{ core, features, wasm }| {
		parsed = features.map_try(JoyRuntime.sections)?
		used = JoyRuntime.used_ids(wasm, operation_ids(parsed))?
		header = "\n// Features this app uses (see tools/runtime): ${if used.is_empty() "none" else Str.join_with(used, ", ")}\n"
		Ok(assemble(core, header, parsed, used)?)
	}

	## The runtime.js for development: `core` and every feature, whatever
	## the app calls. The wasm changes on nearly every edit, and a runtime.js
	## made from it would have to be made again in step with it, so a watch
	## loop serves this one and leaves `generate` to the release build.
	full : { core : Str, features : List(Str) } -> Try(Str, [BadSection(Str), ShortId(Str), MissingHelper(Str)])
	full = |{ core, features }| {
		parsed = features.map_try(JoyRuntime.sections)?
		Ok(assemble(core, "\n// Every feature, for development (see tools/runtime)\n", parsed, operation_ids(parsed))?)
	}

	## The runtime.js for several apps that load it together, the bundles of
	## one build that share one joy.js: `core` and the operations any of
	## `wasms` uses.
	generate_all : { core : Str, features : List(Str), wasms : List(List(U8)) } -> Try(Str, [BadSection(Str), ShortId(Str), NotWasm, BadWasm(Str), MissingHelper(Str)])
	generate_all = |{ core, features, wasms }| {
		parsed = features.map_try(JoyRuntime.sections)?
		ids = operation_ids(parsed)
		per_wasm = wasms.map_try(|wasm| JoyRuntime.used_ids(wasm, ids))?
		used = ids.keep_if(|id| per_wasm.any(|found| found.contains(id)))
		header = "\n// Features these apps use (see tools/runtime): ${if used.is_empty() "none" else Str.join_with(used, ", ")}\n"
		Ok(assemble(core, header, parsed, used)?)
	}
}

## The ids of every operation and event source in the parsed features.
operation_ids : List(List(JoyRuntime.Section)) -> List(Str)
operation_ids = |parsed| parsed.join().keep_if(|s| s.kind != Helper).map(|s| s.name)

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
## app uses none of the feature's operations.
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

## Whether `needle` appears in `haystack`.
contains : List(U8), List(U8) -> Bool
contains = |haystack, needle|
	match needle.first() {
		Err(_) => Bool.True
		Ok(first) => contains_from(haystack, needle, first, 0)
	}

contains_from : List(U8), List(U8), U8, U64 -> Bool
contains_from = |haystack, needle, first, at|
	if at + needle.len() > haystack.len() {
		Bool.False
	} else if haystack.get(at) == Ok(first) and haystack.sublist({ start: at, len: needle.len() }) == needle {
		Bool.True
	} else {
		contains_from(haystack, needle, first, at + 1)
	}

feature_source : Str
feature_source =
	\\// a test feature
	\\
	\\//// helper shared
	\\const shared = 1;
	\\
	\\//// op joy/test/first needs shared
	\\defineOperation('joy/test/first', () => shared);
	\\
	\\//// op joy/test/second
	\\defineOperation('joy/test/second', () => 2);
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

expect JoyRuntime.sections(feature_source).map_ok(|s| s.map(|x| x.name)) == Ok(["shared", "joy/test/first", "joy/test/second"])
expect JoyRuntime.sections("//// op joy/short\nx") == Err(ShortId("joy/short"))
expect JoyRuntime.used_ids(wasm_with("..joy/test/first.."), ["joy/test/first", "joy/test/second"]) == Ok(["joy/test/first"])
expect JoyRuntime.data_bytes([1, 2, 3, 4]) == Err(NotWasm)

expect {
	generated = JoyRuntime.generate({ core: "// core\n", features: [feature_source], wasm: wasm_with("joy/test/first") })
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
