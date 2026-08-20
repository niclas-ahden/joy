# Real-browser E2E: the keyboard example in Chromium. The fake-DOM harness
# calls the host's listeners by hand. Here Playwright's key APIs drive real
# KeyboardEvents through the document, so what's proven is the wiring the
# fake DOM can only assume: document-level subscription listeners receive
# real bubbled keydowns, element handlers and key filters see real key/code
# values, and toggling the subscription set attaches and detaches real
# listeners.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

main! = |_args| {
	{ browser, page } = Support.open!("keyboard", "#listen")?

	# A page-level press reaches the two all-keys document subscriptions (one
	# message each) and lands in the model as the full KeyEvent.
	Playwright.key_press_targetless!(page, KeyS, [])?
	Support.expect_text!(page, "#last-key", "Last key: s (KeyS)", |got| WrongKeyEvent(got))?

	# Escape hits the key-filtered subscription too, and the all-keys ones
	# still count it.
	Playwright.key_press_targetless!(page, Escape, [])?
	Support.expect_text!(page, "#keys-seen", "Keys seen: 2", |got| EscapeNotCounted(got))?
	Support.expect_text!(page, "#escapes", "Escapes: 1", |got| EscapeNotCounted(got))?

	# The first input's own on_keydown fires for that element, and the real
	# keydown bubbles on to the document subscriptions.
	Playwright.key_press!(page, "#typing", KeyA, [])?
	Support.expect_text!(page, "#input-key", "Input key: a", |got| ElementHandlerMissedKey(got))?
	Support.expect_text!(page, "#keys-seen", "Keys seen: 3", |got| ElementHandlerMissedKey(got))?

	# The second input filters on Enter (with prevent_default), so Enter
	# submits...
	Playwright.key_press!(page, "#submitting", Enter, [])?
	# ...and any other key must not.
	Playwright.key_press!(page, "#submitting", KeyQ, [])?
	Support.expect_text!(page, "#submits", "Submits: 1", |got| EnterFilterWrong(got))?

	# "Stop listening" empties the subscription list, which must detach the
	# real document listeners: further keys change nothing. Still 5, which
	# also proves the Enter and Q presses above reached the document.
	Playwright.click!(page, "#listen")?
	Playwright.key_press_targetless!(page, KeyX, [])?
	Support.expect_text!(page, "#keys-seen", "Keys seen: 5", |got| ListenerNotDetached(got))?

	# "Listen" declares them again: fresh listeners, counting resumes.
	Playwright.click!(page, "#listen")?
	Playwright.key_press_targetless!(page, KeyZ, [])?
	Support.expect_text!(page, "#keys-seen", "Keys seen: 6", |got| ListenerNotReattached(got))?

	Playwright.close!(browser)?
	Ok({})
}
