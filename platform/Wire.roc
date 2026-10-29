## The bytes a browser feature's operation is called with and answers with
## (see Effect.call, Effect.send and Sub.listen): its fields one after
## another, in the order the operation defines, with no names and no tags.
## Each operation's Roc function and its JavaScript (www/features/) are a
## pair that agree on the order, the way a function and its caller agree on
## its arguments. Little-endian throughout:
##
## - `U8`, `U16`, `U32`, `U64`, `I64`: fixed width
## - `Bool`: one byte, 0 or 1
## - `Str`: a `U32` byte length, then UTF-8
## - bytes: a `U32` length, then the bytes
## - `List(U16)`: a `U32` count, then the values
##
## ```
## args = Wire.writer({}).u32(stream_id).str(mime_type).done()
##
## summary : List(U8) -> Try({ duration_ms : I64, peaks : List(U16) }, [WireEnded])
## summary = |answer| {
##     (duration_ms, rest) = Wire.reader(answer).i64()?
##     (peaks, _) = rest.u16s()?
##     Ok({ duration_ms, peaks })
## }
## ```
Wire := [].{
	Writer :: List(U8).{
		u8 : Wire.Writer, U8 -> Wire.Writer
		u8 = |w, n| Writer.(w.to_list().append(n))

		bool : Wire.Writer, Bool -> Wire.Writer
		bool = |w, b| w.u8(if b 1 else 0)

		u16 : Wire.Writer, U16 -> Wire.Writer
		u16 = |w, n| Writer.(w.to_list().concat(le(n.to_u64(), 2)))

		u32 : Wire.Writer, U32 -> Wire.Writer
		u32 = |w, n| Writer.(w.to_list().concat(le(n.to_u64(), 4)))

		u64 : Wire.Writer, U64 -> Wire.Writer
		u64 = |w, n| Writer.(w.to_list().concat(le(n, 8)))

		i64 : Wire.Writer, I64 -> Wire.Writer
		i64 = |w, n| w.u64(n.to_u64_wrap())

		bytes : Wire.Writer, List(U8) -> Wire.Writer
		bytes = |w, b| Writer.(w.u32(b.len().to_u32_wrap()).to_list().concat(b))

		str : Wire.Writer, Str -> Wire.Writer
		str = |w, s| w.bytes(s.to_utf8())

		## The bytes written.
		done : Wire.Writer -> List(U8)
		done = |w| w.to_list()

		to_list : Wire.Writer -> List(U8)
		to_list = |Writer.(list)| list
	}

	Reader :: { bytes : List(U8), at : U64 }.{
		u8 : Wire.Reader -> Try((U8, Wire.Reader), [WireEnded])
		u8 = |r| {
			(n, next) = take(r, 1)?
			Ok((n.to_u8_wrap(), next))
		}

		bool : Wire.Reader -> Try((Bool, Wire.Reader), [WireEnded])
		bool = |r| {
			(n, next) = r.u8()?
			Ok((n != 0, next))
		}

		u16 : Wire.Reader -> Try((U16, Wire.Reader), [WireEnded])
		u16 = |r| {
			(n, next) = take(r, 2)?
			Ok((n.to_u16_wrap(), next))
		}

		u32 : Wire.Reader -> Try((U32, Wire.Reader), [WireEnded])
		u32 = |r| {
			(n, next) = take(r, 4)?
			Ok((n.to_u32_wrap(), next))
		}

		u64 : Wire.Reader -> Try((U64, Wire.Reader), [WireEnded])
		u64 = |r| take(r, 8)

		i64 : Wire.Reader -> Try((I64, Wire.Reader), [WireEnded])
		i64 = |r| {
			(n, next) = take(r, 8)?
			Ok((n.to_i64_wrap(), next))
		}

		bytes : Wire.Reader -> Try((List(U8), Wire.Reader), [WireEnded])
		bytes = |r| {
			(len, after_len) = r.u32()?
			Reader.({ bytes, at }) = after_len
			n = len.to_u64()
			if at + n > bytes.len() {
				Err(WireEnded)
			} else {
				Ok((bytes.sublist({ start: at, len: n }), Reader.({ bytes, at: at + n })))
			}
		}

		str : Wire.Reader -> Try((Str, Wire.Reader), [WireEnded])
		str = |r| {
			(b, next) = r.bytes()?
			Ok((Str.from_utf8_lossy(b), next))
		}

		## What is left unread.
		remaining : Wire.Reader -> List(U8)
		remaining = |Reader.({ bytes: all, at })| all.drop_first(at)

		u16s : Wire.Reader -> Try((List(U16), Wire.Reader), [WireEnded])
		u16s = |r| {
			(count, after_count) = r.u32()?
			read_u16s(after_count, count, List.with_capacity(count.to_u64()))
		}
	}

	writer : {} -> Wire.Writer
	writer = |{}| Writer.([])

	reader : List(U8) -> Wire.Reader
	reader = |bytes| Reader.({ bytes, at: 0 })
}

## `n` little-endian bytes of `value`.
le : U64, U64 -> List(U8)
le = |value, n| List.repeat({}, n).map_with_index(|_, i| value.shr_zf_wrap((i * 8).to_u8_wrap()).to_u8_wrap())

## The `n`-byte little-endian number at the reader's position.
take : Wire.Reader, U64 -> Try((U64, Wire.Reader), [WireEnded])
take = |Reader.({ bytes, at }), n|
	if at + n > bytes.len() {
		Err(WireEnded)
	} else {
		value = bytes.sublist({ start: at, len: n }).map_with_index(|b, i| b.to_u64().shl_wrap((i * 8).to_u8_wrap())).fold(0, |acc, part| acc.bitwise_or(part))
		Ok((value, Reader.({ bytes, at: at + n })))
	}

read_u16s : Wire.Reader, U32, List(U16) -> Try((List(U16), Wire.Reader), [WireEnded])
read_u16s = |r, left, acc|
	if left == 0 {
		Ok((acc, r))
	} else {
		(n, next) = r.u16()?
		read_u16s(next, left - 1, acc.append(n))
	}

expect Wire.writer({}).u32(258).str("hej").done() == [2, 1, 0, 0, 3, 0, 0, 0, 104, 101, 106]

expect {
	bytes = Wire.writer({}).i64(-5).bool(Bool.True).u16(513).bytes([9, 8]).done()
	r = Wire.reader(bytes)
	read = {
		(a, r1) = r.i64()?
		(b, r2) = r1.bool()?
		(c, r3) = r2.u16()?
		(d, _) = r3.bytes()?
		Ok((a, b, c, d))
	}
	read == Ok((-5, Bool.True, 513, [9, 8]))
}

expect {
	peaks = [0, 500, 1000]
	bytes = Wire.writer({}).u32(3).u16(0).u16(500).u16(1000).done()
	Wire.reader(bytes).u16s().map_ok(|(list, _)| list) == Ok(peaks)
}

expect Wire.reader([1, 0]).u32().map_ok(|(n, _)| n) == Err(WireEnded)
