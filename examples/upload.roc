app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, div, p, input, button, text]
import html.Attribute exposing [id, type, on_file, on_click]
import pf.Effect exposing [Effect]
import pf.Http
import pf.WebCrypto

# The file pipeline: a file input's `on_file` delivers a typed `FileInfo`
# whose id is a handle to the browser-held File object, so the bytes never
# enter wasm memory. The id feeds `WebCrypto.digest_file` (hash it where the
# bytes live) and `Http.post_file` (stream it as a request body), so hashing
# and uploading a multi-gigabyte file costs no wasm heap at all.

Model : {
	file : [NoFile, Picked(Attribute.FileInfo)],
	hash : Str,
	upload : Str,
}

# GotUploadResponse carries a small decoded payload rather than the usual
# `Try(Http.Response, ...)`: an app that creates both a file callable
# (`on_file`) and an http callback whose Msg embeds the response types
# crashes roc build with an out-of-bounds panic while unifying solved-type
# digests of erased callables, a known compiler bug. Decoding the Try inside
# the callback keeps those types out of Msg and sidesteps it.
Msg : [
	UserPickedFile(Attribute.FileInfo),
	GotHash(List(U8)),
	UserClickedUpload,
	GotUploadResponse([UploadedWithStatus(U16), UploadFailed]),
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ file: NoFile, hash: "", upload: "" }, [])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserPickedFile(info) =>
			(
				{ ..model, file: Picked(info), hash: "hashing...", upload: "" },
				[WebCrypto.digest_file(Sha256, info.id, |h| GotHash(h))],
			)

		GotHash(h) =>
		# An empty hash is WebCrypto's failure signal.
			({ ..model, hash: if h.len() == 0 "hashing failed" else WebCrypto.to_hex(h) }, [])

		UserClickedUpload =>
			match model.file {
				Picked(info) =>
					(
						{ ..model, upload: "uploading..." },
						[
							Http.post_file(
								"/upload",
								info.id,
								[{ name: "x-file-name", value: info.name }],
								|r| match r {
									Ok(resp) => GotUploadResponse(UploadedWithStatus(resp.status))
									Err(HttpErr(_)) => GotUploadResponse(UploadFailed)
								},
							),
						],
					)
				NoFile => (model, [])
			}

		GotUploadResponse(UploadedWithStatus(status)) =>
			({ ..model, upload: "upload status ${status.to_str()}" }, [])

		GotUploadResponse(UploadFailed) =>
			({ ..model, upload: "upload failed" }, [])
		}

render : Model -> Html(Msg)
render = |model| {
	picked = match model.file {
		Picked(info) => "${info.name} (${info.size.to_str()} bytes, ${info.mime})"
		NoFile => "no file yet"
	}
	div(
		[],
		[
			input([id("file"), type("file"), on_file(|f| UserPickedFile(f))]),
			p([id("picked")], [text("picked: ${picked}")]),
			p([id("hash")], [text("sha256: ${model.hash}")]),
			button([id("upload"), on_click(UserClickedUpload)], [text("Upload")]),
			p([id("status")], [text(model.upload)]),
		],
	)
}
