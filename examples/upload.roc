app [Model, Msg, init, update, view, subscriptions] {
	pf: platform "../platform/main.roc",
	html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc1/6eTqakHk59tsBefdx2VPuYDVZxG8SoEtzE74e7MzyoBq.tar.zst",
}

import html.Html exposing [div, p, input, button, text]
import html.Attribute exposing [id, type, on_file, on_click]
import pf.Effect
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

Msg : [
	UserPickedFile(Attribute.FileInfo),
	GotHash(List(U8)),
	UserClickedUpload,
	GotUploadResponse(Try(Http.Response, [HttpErr([Timeout, NetworkError])])),
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
								|r| GotUploadResponse(r),
							),
						],
					)
				NoFile => (model, [])
			}

		GotUploadResponse(Ok(resp)) =>
			({ ..model, upload: "upload status ${resp.status.to_str()}" }, [])

		GotUploadResponse(Err(_)) =>
			({ ..model, upload: "upload failed" }, [])
		}

view : Model -> Html(Msg)
view = |model| {
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
