# Real-browser E2E: the upload example in Chromium, the whole file pipeline
# on the real APIs the fake DOM stubs out: set_input_files! puts an actual
# File behind the input, on_file's FileInfo reflects it, WebCrypto.digest_file
# hashes it with the browser's own crypto.subtle, and Http.post_file streams
# it to the dev server's POST /upload (see www/serve.mjs), whose status comes
# back through the callback.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

# 79 bytes. The hex is `printf '...\n' | sha256sum` of the same content, so
# the assertion catches a digest of the wrong bytes, not just a wrong format.
content = "Joy streams these bytes straight from the browser. The wasm never copies them.\n"
content_sha256 = "sha256: 8c42a10b9677385bcd3ac511337917a9e2055f38cb54610727c38c5e90879995"

main! = |_args| {
	{ browser, page } = Support.open!("upload", "#file")?

	Playwright.set_input_files!(
		page,
		"#file",
		Buffers([{ name: "notes.txt", mime_type: "text/plain", buffer: Str.to_utf8(content) }]),
	)?

	# The typed FileInfo (name, size, mime) renders synchronously with the
	# change event. The digest is async, so poll for it.
	Support.expect_text!(page, "#picked", "picked: notes.txt (79 bytes, text/plain)", |got| WrongFileInfo(got))?
	Support.wait_for_text!(page, "#hash", content_sha256)?

	# Upload: a real fetch streaming the File as the body, answered 200 by
	# serve.mjs.
	Playwright.click!(page, "#upload")?
	Support.wait_for_text!(page, "#status", "upload status 200")?

	Playwright.close!(browser)?
	Ok({})
}
