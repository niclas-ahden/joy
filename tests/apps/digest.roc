app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, p, input, button, text]
import html.Attribute exposing [type, on_file, on_click]
import pf.Effect exposing [Effect]
import pf.WebCrypto

# Fixture for check_digest.mjs, the three digest paths check_upload.mjs does
# not reach: hashing in-memory bytes (they cross into JS, unlike a file's), a
# byte range of a picked file, and the empty-hash failure signal for a file
# id the browser does not hold.

Model : { mem : Str, slice : Str, missing : Str }

Msg : [
	UserClickedHashMem,
	GotMemHash(List(U8)),
	UserPickedFile(Attribute.FileInfo),
	GotSliceHash(List(U8)),
	UserClickedHashMissing,
	GotMissingHash(List(U8)),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ mem: "", slice: "", missing: "" }, [])

show = |hash| if hash.len() == 0 "failed" else WebCrypto.to_hex(hash)

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedHashMem =>
			(
				{ ..model, mem: "hashing..." },
				[WebCrypto.digest(Sha384, "hello joy".to_utf8(), |h| GotMemHash(h))],
			)

		GotMemHash(h) => ({ ..model, mem: show(h) }, [])

		UserPickedFile(info) =>
			(
				{ ..model, slice: "hashing..." },
				[WebCrypto.digest_file_slice(Sha256, { file: info.id, start: 2, len: 5 }, |h| GotSliceHash(h))],
			)

		GotSliceHash(h) => ({ ..model, slice: show(h) }, [])

		UserClickedHashMissing =>
			(
				{ ..model, missing: "hashing..." },
				[WebCrypto.digest_file(Sha256, 999999, |h| GotMissingHash(h))],
			)

		GotMissingHash(h) => ({ ..model, missing: show(h) }, [])
	}

render : Model -> Html(Msg)
render = |model|
	div(
		[],
		[
			button([on_click(UserClickedHashMem)], [text("Hash memory")]),
			p([], [text("mem: ${model.mem}")]),
			input([type("file"), on_file(|f| UserPickedFile(f))]),
			p([], [text("slice: ${model.slice}")]),
			button([on_click(UserClickedHashMissing)], [text("Hash missing")]),
			p([], [text("missing: ${model.missing}")]),
		],
	)
