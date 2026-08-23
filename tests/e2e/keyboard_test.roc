# Real-browser E2E: the keyboard example in Chromium. The fake-DOM harness
# calls the host's listeners by hand. Here Playwright's key APIs drive real
# KeyboardEvents through the document, so what's proven is the wiring the
# fake DOM can only assume: document-level subscription listeners receive
# real bubbled keydowns, element handlers and key filters see real key/code
# values, and toggling the subscription set attaches and detaches real
# listeners.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import playwright.Playwright exposing [assert!, assert_with!]
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("keyboard", "#listen")?

	# A page-level press reaches the two all-keys document subscriptions (one
	# message each) and lands in the model as the full KeyEvent.
	page.key_press_targetless!(KeyS, [])?
	assert!(page.find("#last-key").has_text("Last key: s (KeyS)"))?

	# Escape hits the key-filtered subscription too, and the all-keys ones
	# still count it.
	page.key_press_targetless!(Escape, [])?
	assert!(page.find("#keys-seen").has_text("Keys seen: 2"))?
	assert!(page.find("#escapes").has_text("Escapes: 1"))?

	# The first input's own on_keydown fires for that element, and the real
	# keydown bubbles on to the document subscriptions.
	page.key_press!("#typing", KeyA, [])?
	assert!(page.find("#input-key").has_text("Input key: a"))?
	assert!(page.find("#keys-seen").has_text("Keys seen: 3"))?

	# The second input filters on Enter (with prevent_default), so Enter
	# submits...
	page.key_press!("#submitting", Enter, [])?
	# ...and any other key must not.
	page.key_press!("#submitting", KeyQ, [])?
	assert!(page.find("#submits").has_text("Submits: 1"))?

	# "Stop listening" empties the subscription list, which must detach the
	# real document listeners: further keys change nothing. Still 5, which
	# also proves the Enter and Q presses above reached the document.
	page.find("#listen").click!()?
	page.key_press_targetless!(KeyX, [])?
	assert_with!(page.find("#keys-seen").has_text("Keys seen: 5"), { label: "listener not detached" })?

	# "Listen" declares them again: fresh listeners, counting resumes.
	page.find("#listen").click!()?
	page.key_press_targetless!(KeyZ, [])?
	assert_with!(page.find("#keys-seen").has_text("Keys seen: 6"), { label: "listener not reattached" })?

	browser.close!()?
	Ok({})
}
