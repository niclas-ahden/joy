## Hash data with the browser's Web Crypto.
##
## ## When to use it
##
## For bytes your app already holds, Roc's built-in `Crypto` module is the
## simpler tool: `Crypto.SHA256.hash(bytes)` gives you the hash right away,
## with no effect. This module is for what the built-in cannot do:
##
## - Hash a file the user picked. The browser reads the file where it is, so
##   its bytes never enter your app.
## - SHA-1, SHA-384 and SHA-512, which the built-in does not have.
##
## A file input tells you about a picked file with `on_file` (in joy-html's
## `Attribute`), and what it gives you has the file's `id`:
##
## ```roc
## WebCrypto.digest_file(
##     Sha256,
##     file.id,
##     |hash| GotHash(hash),
## )
## ```
##
## ## What you get back
##
## The hash as bytes: 20 for `Sha1`, 32 for `Sha256`, 48 for `Sha384` and 64
## for `Sha512`. [WebCrypto.to_hex] turns them into the usual text form.
##
## An empty list means the hashing failed: the file is not known, or it
## changed on disk after it was picked.
##
## ## Big files
##
## [WebCrypto.digest_file] holds the whole file in memory while it hashes. For
## a big file, hash it a part at a time with [WebCrypto.digest_file_slice],
## one effect for each part. That also lets you show progress.
##
## You can ask for every part at once. Joy hashes as many at a time as the
## machine has processor cores and starts the rest as those finish, so only
## that many parts are in memory.
import Effect
import Wire

WebCrypto := [].{

	## The kinds of hash Web Crypto can make.
	##
	## `Sha1` is no longer safe for anything that guards against tampering. It is
	## here for systems that already use it.
	Algorithm : [Sha1, Sha256, Sha384, Sha512]

	## An algorithm's name as Web Crypto spells it, like `"SHA-256"`.
	algorithm_name : Algorithm -> Str
	algorithm_name = |algorithm|
		match algorithm {
			Sha1 => "SHA-1"
			Sha256 => "SHA-256"
			Sha384 => "SHA-384"
			Sha512 => "SHA-512"
		}

	## Hash bytes your app holds.
	##
	## ```roc
	## WebCrypto.digest(Sha384, bytes, |hash| GotHash(hash))
	## ```
	##
	## For `Sha256`, the built-in `Crypto.SHA256.hash(bytes)` does the same with
	## no effect.
	digest : Algorithm, List(U8), (List(U8) -> msg) -> Effect(msg)
	digest = |algorithm, bytes, on_hash|
		Effect.call("joy/crypto/digest", Wire.writer({}).str(algorithm_name(algorithm)).bytes(bytes).done(), |reply| on_hash(hash(reply)))

	## Hash a file the user picked, by its `id`.
	##
	## ```roc
	## WebCrypto.digest_file(Sha256, file.id, |hash| GotHash(hash))
	## ```
	digest_file : Algorithm, U32, (List(U8) -> msg) -> Effect(msg)
	digest_file = |algorithm, file, on_hash| digest_range(algorithm, file, 0, 0, on_hash)

	## Hash a part of a file the user picked. `start` and `len` say which bytes,
	## and a `len` of 0 means all the rest.
	##
	## ```roc
	## WebCrypto.digest_file_slice(
	##     Sha256,
	##     { file: file.id, start: 0, len: 1_000_000 },
	##     |hash| GotPartHash(hash),
	## )
	## ```
	digest_file_slice : Algorithm, { file : U32, start : U64, len : U64 }, (List(U8) -> msg) -> Effect(msg)
	digest_file_slice = |algorithm, slice, on_hash| digest_range(algorithm, slice.file, slice.start, slice.len, on_hash)

	## A hash as text, the way hashes are usually shown: two lowercase hex digits
	## for each byte.
	##
	## ```roc
	## WebCrypto.to_hex([222, 173, 190, 239]) == "deadbeef"
	## ```
	to_hex : List(U8) -> Str
	to_hex = |bytes| {
		pairs = bytes.map(
			|b| {
				digits = "0123456789abcdef".to_utf8()
				hi = digits.get((b // 16).to_u64()) ?? '0'
				lo = digits.get((b % 16).to_u64()) ?? '0'
				Str.from_utf8_lossy([hi, lo])
			},
		)
		Str.join_with(pairs, "")
	}
}

## A byte range of a browser-held file, `len` 0 for through the end.
digest_range : WebCrypto.Algorithm, U32, U64, U64, (List(U8) -> msg) -> Effect(msg)
digest_range = |algorithm, file, start, len, on_hash|
	Effect.call(
		"joy/crypto/digest_file",
		Wire.writer({}).str(WebCrypto.algorithm_name(algorithm)).u32(file).u64(start).u64(len).done(),
		|reply| on_hash(hash(reply)),
	)

## The hash a reply carries, empty when the digest failed.
hash : List(U8) -> List(U8)
hash = |reply| Effect.reply(reply) ?? []

expect hash([0, 1, 2]) == [1, 2]
expect hash([1, 110, 111]) == []

expect WebCrypto.digest_file_slice(Sha256, { file: 3, start: 16, len: 8 }, |h| h.len()).identity() == { id: "joy/crypto/digest_file", args: Wire.writer({}).str("SHA-256").u32(3).u64(16).u64(8).done() }

expect WebCrypto.to_hex([]) == ""
expect WebCrypto.to_hex([0x00]) == "00"
expect WebCrypto.to_hex([0x0F]) == "0f"
expect WebCrypto.to_hex([0xF0]) == "f0"
expect WebCrypto.to_hex([0xFF]) == "ff"
expect WebCrypto.to_hex([0xDE, 0xAD, 0xBE, 0xEF]) == "deadbeef"

# Agrees with the builtin Crypto's own hex rendering on a real 32-byte hash.
expect {
	digest = Crypto.SHA256.hash("abc".to_utf8())
	WebCrypto.to_hex(digest.to_bytes()) == digest.to_hex()
}

expect WebCrypto.algorithm_name(Sha1) == "SHA-1"
expect WebCrypto.algorithm_name(Sha256) == "SHA-256"
expect WebCrypto.algorithm_name(Sha384) == "SHA-384"
expect WebCrypto.algorithm_name(Sha512) == "SHA-512"
