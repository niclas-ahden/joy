module [
    HashAlgorithm,
    Parallelism,
    hash_file_chunks!,
]

import Host

## Supported hash algorithms for SubtleCrypto.digest().
HashAlgorithm : [Sha1, Sha256, Sha384, Sha512]

## Controls how many Web Workers are used for parallel hashing.
Parallelism : [UseAllCores, Exact U32]

parallelism_to_i64 : Parallelism -> I64
parallelism_to_i64 = |p|
    when p is
        UseAllCores -> 0
        Exact(n) -> Num.to_i64(n)

algorithm_to_str : HashAlgorithm -> Str
algorithm_to_str = |algorithm|
    when algorithm is
        Sha1 -> "SHA-1"
        Sha256 -> "SHA-256"
        Sha384 -> "SHA-384"
        Sha512 -> "SHA-512"

## Hash each chunk of a browser File using Web Workers + SubtleCrypto.
##
## The file is split into chunks and hashed concurrently across `parallelism`
## Web Workers using hardware-accelerated SubtleCrypto.
##
## `chunk_size_bytes` must be at least 1 (zero is clamped to 1).
##
## Fires `chunk_event` for each chunk (may arrive out of order):
## ```
## {
##   "file_id": <id>,
##   "total_chunks": <n>,
##   "chunk": { "index": <n>, "starts_at_byte": <n>, "ends_at_byte": <n>, "hash": "<hex>" }
## }
## ```
##
## Fires `done_event` after all chunks are hashed:
## - Success: `{"file_id":<id>,"ok":{"total_chunks":<n>,"hash_of_chunk_hashes":"<hex>"}}`
## - Failure: `{"file_id":<id>,"err":"<message>"}`
##
## `file_id` is included in all payloads so concurrent hash operations
## can be distinguished.
##
## ```
## Crypto.hash_file_chunks!(file_id, {
##     algorithm: Sha1,
##     chunk_size_bytes: 16_000_000,
##     parallelism: UseAllCores,
##     chunk_event: "ChunkHashed",
##     done_event: "AllChunksHashed",
## })
## ```
hash_file_chunks! : U32, { algorithm : HashAlgorithm, chunk_size_bytes : U64, parallelism : Parallelism, chunk_event : Str, done_event : Str } => {}
hash_file_chunks! = |file_id, { algorithm, chunk_size_bytes, parallelism, chunk_event, done_event }|
    Host.crypto_hash_file_chunks!(file_id, algorithm_to_str(algorithm), chunk_size_bytes, parallelism_to_i64(parallelism), chunk_event, done_event)
