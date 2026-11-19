## How the Roc and the JavaScript of a custom effect pass values to each
## other.
##
## You only need this module when you write a custom effect or a subscription
## of your own, with [Effect.call], [Effect.send] or [Sub.listen]. The guide's
## page on [custom effects](../../#custom-effects) walks through it.
##
## ## How it works
##
## Values go across as bytes, one after another, with no names. The Roc and
## the JavaScript agree on the order, the way a function and its caller agree
## on its arguments.
##
## Writing, to call the JavaScript:
##
## ```roc
## args = Wire.writer({}).u32(stream_id).str(mime_type).done()
## ```
##
## Reading, what the JavaScript answered:
##
## ```roc
## summary : List(U8) -> Try(Summary, Wire.Problem)
## summary = |answer| {
##     (duration_ms, rest) = Wire.reader(answer).i64()?
##     (peaks, _) = rest.u16s()?
##     Ok({ duration_ms, peaks })
## }
## ```
##
## Each read gives you the value and a reader for what comes after it.
##
## ## What can go across
##
## | Roc type | Method | In JavaScript |
## |---|---|---|
## | `Str` | `str` | a string |
## | `Bool` | `bool` | true or false |
## | `U8`, `U16`, `U32` | `u8`, `u16`, `u32` | a number |
## | `U64`, `I64` | `u64`, `i64` | a whole number |
## | `F64` | `f64` | a number |
## | `List(U8)` | `bytes` | a Uint8Array |
## | `List(U16)` | `u16s` | a list of numbers |
##
## A record goes across field by field, and a list as its length and then its
## items.
##
## ## When the two sides disagree
##
## Every value has a mark in front that says what kind it is. So reading a
## `Str` where the JavaScript wrote a `Bool` is an error that says where, not
## a wrong value. See [Wire.Problem].
##
## ## The bytes themselves
##
## After its mark, each value is little-endian:
##
## - `U8`, `U16`, `U32`, `U64`, `I64`: fixed width.
## - `F64`: its eight bytes, as IEEE 754 has them.
## - `Bool`: one byte, 0 or 1.
## - `Str`: a `U32` byte length, then UTF-8.
## - bytes: a `U32` length, then the bytes.
## - `List(U16)`: a `U32` count, then the values.
Wire := [].{

	## Why a read gave nothing. Both mean that the Roc and the JavaScript of an
	## effect disagree on what is passed.
	##
	## - `WireEnded`: the bytes ran out. The JavaScript wrote fewer values than
	##   the Roc reads.
	## - `WireMismatch`: the value there is of another kind than the one read.
	##   `value` says which one, counting from 1, `wanted` what the Roc read and
	##   `found` what was there.
	Problem : [WireEnded, WireMismatch({ value : U64, wanted : Str, found : Str })]

	## A problem in words, for you to read while you write the two sides.
	##
	## ```roc
	## (language, _) = Wire.reader(answer).str() ? Wire.explain
	## ```
	explain : Problem -> Str
	explain = |problem|
		match problem {
			WireEnded => "The bytes ended before everything was read: the JavaScript wrote fewer values than the Roc reads."
			WireMismatch({ value, wanted, found }) => "Value ${value.to_str()} is ${found}, where the Roc reads ${wanted}. The JavaScript and the Roc disagree on what is passed, or on its order."
		}

	## Writes values, one after another. Start with [Wire.writer], add each value
	## with the method for its type, and end with `done`:
	##
	## ```roc
	## Wire.writer({}).str("memo").u32(3).bool(Bool.True).done()
	## ```
	Writer :: List(U8).{
		u8 : Wire.Writer, U8 -> Wire.Writer
		u8 = |w, n| put(w, tag_u8, [n])

		bool : Wire.Writer, Bool -> Wire.Writer
		bool = |w, b| put(w, tag_bool, [if (b) 1 else 0])

		u16 : Wire.Writer, U16 -> Wire.Writer
		u16 = |w, n| put(w, tag_u16, le(n.to_u64(), 2))

		u32 : Wire.Writer, U32 -> Wire.Writer
		u32 = |w, n| put(w, tag_u32, le(n.to_u64(), 4))

		u64 : Wire.Writer, U64 -> Wire.Writer
		u64 = |w, n| put(w, tag_u64, le(n, 8))

		i64 : Wire.Writer, I64 -> Wire.Writer
		i64 = |w, n| put(w, tag_i64, le(n.to_u64_wrap(), 8))

		f64 : Wire.Writer, F64 -> Wire.Writer
		f64 = |w, n| put(w, tag_f64, le(F64.to_bits(n), 8))

		bytes : Wire.Writer, List(U8) -> Wire.Writer
		bytes = |w, b| put(w, tag_bytes, le(b.len(), 4).concat(b))

		str : Wire.Writer, Str -> Wire.Writer
		str = |w, s| {
			b = s.to_utf8()
			put(w, tag_str, le(b.len(), 4).concat(b))
		}

		u16s : Wire.Writer, List(U16) -> Wire.Writer
		u16s = |w, list| put(w, tag_u16s, le(list.len(), 4).concat(list.map(|n| le(n.to_u64(), 2)).join()))

		## The bytes written, to hand to [Effect.call], [Effect.send] or [Sub.listen].
		done : Wire.Writer -> List(U8)
		done = |w| w.to_list()

		to_list : Wire.Writer -> List(U8)
		to_list = |Writer.(list)| list
	}

	## Reads values, one after another, in the order they were written. Start
	## with [Wire.reader]. Each method gives you the value and a reader for the
	## rest, or a [Wire.Problem]:
	##
	## ```roc
	## (name, rest) = Wire.reader(answer).str()?
	## (count, _) = rest.u32()?
	## ```
	Reader :: { bytes : List(U8), at : U64, read : U64 }.{
		u8 : Wire.Reader -> Try((U8, Wire.Reader), Wire.Problem)
		u8 = |r| {
			(n, next) = number(tagged(r, tag_u8)?, 1)?
			Ok((n.to_u8_wrap(), next))
		}

		bool : Wire.Reader -> Try((Bool, Wire.Reader), Wire.Problem)
		bool = |r| {
			(n, next) = number(tagged(r, tag_bool)?, 1)?
			Ok((n != 0, next))
		}

		u16 : Wire.Reader -> Try((U16, Wire.Reader), Wire.Problem)
		u16 = |r| {
			(n, next) = number(tagged(r, tag_u16)?, 2)?
			Ok((n.to_u16_wrap(), next))
		}

		u32 : Wire.Reader -> Try((U32, Wire.Reader), Wire.Problem)
		u32 = |r| {
			(n, next) = number(tagged(r, tag_u32)?, 4)?
			Ok((n.to_u32_wrap(), next))
		}

		u64 : Wire.Reader -> Try((U64, Wire.Reader), Wire.Problem)
		u64 = |r| number(tagged(r, tag_u64)?, 8)

		i64 : Wire.Reader -> Try((I64, Wire.Reader), Wire.Problem)
		i64 = |r| {
			(n, next) = number(tagged(r, tag_i64)?, 8)?
			Ok((n.to_i64_wrap(), next))
		}

		f64 : Wire.Reader -> Try((F64, Wire.Reader), Wire.Problem)
		f64 = |r| {
			(n, next) = number(tagged(r, tag_f64)?, 8)?
			Ok((F64.from_bits(n), next))
		}

		bytes : Wire.Reader -> Try((List(U8), Wire.Reader), Wire.Problem)
		bytes = |r| sized(tagged(r, tag_bytes)?)

		str : Wire.Reader -> Try((Str, Wire.Reader), Wire.Problem)
		str = |r| {
			(b, next) = sized(tagged(r, tag_str)?)?
			Ok((Str.from_utf8_lossy(b), next))
		}

		u16s : Wire.Reader -> Try((List(U16), Wire.Reader), Wire.Problem)
		u16s = |r| {
			(count, after_count) = number(tagged(r, tag_u16s)?, 4)?
			read_u16s(after_count, count, List.with_capacity(count))
		}

		## What is left unread, as raw bytes. This is for bytes that were not written
		## through a writer, which have no marks to read them by.
		remaining : Wire.Reader -> List(U8)
		remaining = |Reader.({ bytes: all, at, read: _ })| all.drop_first(at)
	}

	## A writer with nothing written yet.
	writer : {} -> Wire.Writer
	writer = |{}| Writer.([])

	## A reader at the start of some bytes.
	reader : List(U8) -> Wire.Reader
	reader = |bytes| Reader.({ bytes, at: 0, read: 0 })
}

# The byte in front of each value. www/runtime.js has the same ones.
tag_u8 = 1

tag_u16 = 2

tag_u32 = 3

tag_u64 = 4

tag_i64 = 5

tag_f64 = 6

tag_bool = 7

tag_bytes = 8

tag_str = 9

tag_u16s = 10

## What a tag stands for, in words.
kind : U8 -> Str
kind = |tag|
	match tag {
		1 => "a U8"
		2 => "a U16"
		3 => "a U32"
		4 => "a U64"
		5 => "an I64"
		6 => "an F64"
		7 => "a Bool"
		8 => "bytes"
		9 => "a Str"
		10 => "a List(U16)"
		_ => "no value a writer wrote"
	}

## A value's tag and bytes at the end of what is written.
put : Wire.Writer, U8, List(U8) -> Wire.Writer
put = |Writer.(list), tag, bytes| Writer.(list.append(tag).concat(bytes))

## `n` little-endian bytes of `value`.
le : U64, U64 -> List(U8)
le = |value, n| List.repeat({}, n).map_with_index(|_, i| value.shr_zf_wrap((i * 8).to_u8_wrap()).to_u8_wrap())

## Past the tag of the next value, which has to be `wanted`.
tagged : Wire.Reader, U8 -> Try(Wire.Reader, Wire.Problem)
tagged = |Reader.({ bytes, at, read }), wanted|
	match bytes.get(at) {
		Ok(found) =>
			if found == wanted {
				Ok(Reader.({ bytes, at: at + 1, read: read + 1 }))
			} else {
				Err(WireMismatch({ value: read + 1, wanted: kind(wanted), found: kind(found) }))
			}

		Err(_) => Err(WireEnded)
	}

## The `n`-byte little-endian number at the reader's position.
number : Wire.Reader, U64 -> Try((U64, Wire.Reader), Wire.Problem)
number = |Reader.({ bytes, at, read }), n|
	if at + n > bytes.len() {
		Err(WireEnded)
	} else {
		value = bytes.sublist({ start: at, len: n }).map_with_index(|b, i| b.to_u64().shl_wrap((i * 8).to_u8_wrap())).fold(0, |acc, part| acc.bitwise_or(part))
		Ok((value, Reader.({ bytes, at: at + n, read })))
	}

## The bytes at the reader's position that a `U32` length is in front of.
sized : Wire.Reader -> Try((List(U8), Wire.Reader), Wire.Problem)
sized = |r| {
	(len, Reader.({ bytes, at, read })) = number(r, 4)?
	if at + len > bytes.len() {
		Err(WireEnded)
	} else {
		Ok((bytes.sublist({ start: at, len }), Reader.({ bytes, at: at + len, read })))
	}
}

read_u16s : Wire.Reader, U64, List(U16) -> Try((List(U16), Wire.Reader), Wire.Problem)
read_u16s = |r, left, acc|
	if left == 0 {
		Ok((acc, r))
	} else {
		(n, next) = number(r, 2)?
		read_u16s(next, left - 1, acc.append(n.to_u16_wrap()))
	}

# A tag, then the value.
expect Wire.writer({}).u32(258).str("hej").done() == [3, 2, 1, 0, 0, 9, 3, 0, 0, 0, 104, 101, 106]

expect {
	bytes = Wire.writer({}).i64(-5).bool(Bool.True).u16(513).bytes([9, 8]).u8(7).u64(9).done()
	r = Wire.reader(bytes)
	read = {
		(a, r1) = r.i64()?
		(b, r2) = r1.bool()?
		(c, r3) = r2.u16()?
		(d, r4) = r3.bytes()?
		(e, r5) = r4.u8()?
		(f, _) = r5.u64()?
		Ok((a, b, c, d, e, f))
	}
	read == Ok((-5, Bool.True, 513, [9, 8], 7, 9))
}

expect Wire.reader(Wire.writer({}).u16s([0, 500, 1000]).done()).u16s().map_ok(|(list, _)| list) == Ok([0, 500, 1000])

# The bytes end: with nothing left, in the middle of a number, in the middle of a string.
expect Wire.reader([]).u32().map_ok(|(n, _)| n) == Err(WireEnded)
expect Wire.reader([3, 1, 0]).u32().map_ok(|(n, _)| n) == Err(WireEnded)
expect Wire.reader([9, 5, 0, 0, 0, 104]).str().map_ok(|(s, _)| s) == Err(WireEnded)

# A value of another kind is named with its place, where it would have been read as some other number.
expect Wire.reader(Wire.writer({}).str("a").f64(640.0).bool(Bool.True).done()).str().map_ok(|(_, rest)| rest.bool().map_ok(|(b, _)| b)) == Ok(Err(WireMismatch({ value: 2, wanted: "a Bool", found: "an F64" })))
expect Wire.reader(Wire.writer({}).u32(1).done()).u16().map_ok(|(n, _)| n) == Err(WireMismatch({ value: 1, wanted: "a U16", found: "a U32" }))
expect Wire.reader([104, 105]).str().map_ok(|(s, _)| s) == Err(WireMismatch({ value: 1, wanted: "a Str", found: "no value a writer wrote" }))
expect Wire.explain(WireMismatch({ value: 2, wanted: "a Bool", found: "an F64" })) == "Value 2 is an F64, where the Roc reads a Bool. The JavaScript and the Roc disagree on what is passed, or on its order."

# What is not written through a writer is read as it is.
expect Wire.reader([104, 105]).remaining() == [104, 105]
expect Wire.reader(Wire.writer({}).u8(1).done().concat([104, 105])).u8().map_ok(|(_, rest)| rest.remaining()) == Ok([104, 105])

# 59.3293 as JavaScript writes it: new DataView(...).setFloat64(0, 59.3293, true).
expect Wire.reader([6, 82, 73, 157, 128, 38, 170, 77, 64]).f64().map_ok(|(n, _)| n.to_str()) == Ok("59.3293")
expect Wire.writer({}).f64(59.3293).done() == [6, 82, 73, 157, 128, 38, 170, 77, 64]
expect Wire.reader(Wire.writer({}).f64(-0.5).done()).f64().map_ok(|(n, _)| n.to_str()) == Ok("-0.5")
