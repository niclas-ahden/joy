# Real-browser E2E: the upload example in Chromium, the whole file pipeline
# on the real APIs the fake DOM stubs out: set_input_files! puts an actual
# File behind the input, on_file's FileInfo reflects it, WebCrypto.digest_file
# hashes it with the browser's own crypto.subtle, and Http.post_file streams
# it to the dev server's POST /upload (see www/serve.mjs), whose status comes
# back through the callback.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!]
import Browser

# 79 bytes. The hex is `printf '...\n' | sha256sum` of the same content, so
# the assertion catches a digest of the wrong bytes, not just a wrong format.
content = "Joy streams these bytes straight from the browser. The wasm never copies them.\n"
content_sha256 = "sha256: 8c42a10b9677385bcd3ac511337917a9e2055f38cb54610727c38c5e90879995"

main! = |_args| {
	{ browser, page } = Browser.open!("upload", "#file")?

	page.set_input_files!(
		"#file",
		Buffers([{ name: "notes.txt", mime_type: "text/plain", buffer: Str.to_utf8(content) }]),
	)?

	# The typed FileInfo (name, size, mime) renders synchronously with the
	# change event. The digest is async, and assert! re-checks until it lands.
	assert!(page.find("#picked").has_text("picked: notes.txt (79 bytes, text/plain)"))?
	assert!(page.find("#hash").has_text(content_sha256))?

	# Upload: a real fetch streaming the File as the body, answered 200 by
	# serve.mjs.
	page.find("#upload").click!()?
	assert!(page.find("#status").has_text("upload status 200"))?

	browser.close!()?
	Ok({})
}
