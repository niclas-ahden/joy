## Hashing via the browser's Web Crypto (`crypto.subtle.digest`), as
## effects: the digest runs asynchronously on the JS side and the hash
## arrives in `update` as a typed message.
##
## For bytes you already have, prefer Roc's built-in `Crypto` module
## (`Crypto.SHA256.hash(bytes)` / `Crypto.BLAKE3.hash(bytes)`): it is pure,
## synchronous, and needs no effect round-trip. This module earns its keep
## where the builtin cannot go: hashing a user-picked FILE (see
## `Attribute.on_file`) whose bytes live on the browser side and never enter
## wasm memory, and the SHA-1/SHA-384/SHA-512 algorithms the builtin does
## not provide. For chunked hashing of large files (progress reporting, or a
## hash-of-chunk-hashes scheme), issue one `digest_file_slice` per chunk
## (the browser runs them concurrently) and hash the concatenated chunk
## hashes at the end.
##
## The callback receives the raw hash bytes (20 for Sha1, 32 for Sha256, 48
## for Sha384, 64 for Sha512). An EMPTY list means the digest failed (unknown
## file id, or the file changed on disk after being picked).
import Effect exposing [Effect]

WebCrypto := [].{

	## Web Crypto's supported digest algorithms. Sha1 is broken for
	## collision resistance; it is here for interop with systems keyed on
	## it, not for anything security-sensitive.
	Algorithm : [Sha1, Sha256, Sha384, Sha512]

	## The Web Crypto name of an algorithm ("SHA-256", ...).
	algorithm_name : Algorithm -> Str
	algorithm_name = |algorithm|
		match algorithm {
			Sha1 => "SHA-1"
			Sha256 => "SHA-256"
			Sha384 => "SHA-384"
			Sha512 => "SHA-512"
		}

	## Hash bytes: `WebCrypto.digest(Sha384, bytes, |hash| GotHash(hash))`.
	## (For Sha256, the built-in `Crypto.SHA256.hash` is the better tool.)
	digest : Algorithm, List(U8), (List(U8) -> msg) -> Effect(msg)
	digest = |algorithm, bytes, on_hash|
		Effect.crypto_digest(algorithm_name(algorithm), bytes, on_hash)

	## Hash a user-picked file by its `Attribute.FileInfo` id.
	digest_file : Algorithm, U32, (List(U8) -> msg) -> Effect(msg)
	digest_file = |algorithm, file, on_hash|
		Effect.crypto_digest_file(algorithm_name(algorithm), file, 0, 0, on_hash)

	## Hash a byte range of a user-picked file (`len` 0 means through the
	## end). One call per chunk gives chunked hashing with progress.
	digest_file_slice : Algorithm, { file : U32, start : U64, len : U64 }, (List(U8) -> msg) -> Effect(msg)
	digest_file_slice = |algorithm, slice, on_hash|
		Effect.crypto_digest_file(algorithm_name(algorithm), slice.file, slice.start, slice.len, on_hash)

	## The conventional lowercase-hex rendering of a hash.
	to_hex : List(U8) -> Str
	to_hex = |bytes|
		bytes.map(
			|b| {
				digits = "0123456789abcdef".to_utf8()
				hi = digits.get((b // 16).to_u64()) ?? '0'
				lo = digits.get((b % 16).to_u64()) ?? '0'
				Str.from_utf8_lossy([hi, lo])
			},
		)
			|> Str.join_with("")
}

# --- roc test (run via `roc test platform/main.roc`) ---

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
