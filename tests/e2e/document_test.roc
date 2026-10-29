# Real-browser E2E: DOM.set_title, DOM.scroll_to, DOM.on_document_click,
# Clipboard.write_text and Clipboard.write_text_of. The fake DOM can only
# record the calls, so this is what a real browser adds: the tab's title
# changes, a page clicked from far down returns to the top, a click on HTML
# the app never rendered reaches it, and the browser lets a click write to
# the clipboard.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page, can_read_clipboard } = Browser.open_with_clipboard!("document", "#next")?

	Assert.eq(page.evaluate!("document.title")?, "Page 1") ? |e| InitShouldNameThePage(Str.inspect(e))

	# Clicking the foot's "Next" scrolls down to it first, then the update
	# returns DOM.scroll_to({ x: 0, y: 0 }).
	page.find("#next-at-foot").click!()?
	assert!(page.find("#page").has_text("page 2"))?
	Assert.eq(page.evaluate!("document.title")?, "Page 2") ? |e| UpdateShouldRenameThePage(Str.inspect(e))
	Assert.eq(page.evaluate!("String(window.scrollY)")?, "0") ? |e| PageShouldBeBackAtTheTop(Str.inspect(e))

	# A click is the user activation the clipboard wants.
	page.find("#copy").click!()?
	assert!(page.find("#copied").has_text("copied the text"))?
	if can_read_clipboard {
		Assert.eq(page.evaluate!("navigator.clipboard.readText()")?, "roc build") ? |e| TheTextShouldBeOnTheClipboard(Str.inspect(e))
	} else {
		{}
	}

	# HTML of the page's own beside the app's root, as a static page would
	# have it. evaluate! wants a value back, so the expression ends with one.
	_ = page.evaluate!("(document.body.insertAdjacentHTML('beforeend', '<div data-pick=\"outer\"><span id=\"in-outer\">inside</span></div><pre id=\"source\">joy <b>dev</b></pre>'), 'added')")?
	page.find("#in-outer").click!()?
	assert!(page.find("#picked").has_text("picked: outer"))?

	page.find("#copy-source").click!()?
	assert!(page.find("#copied").has_text("copied #source"))?
	if can_read_clipboard {
		Assert.eq(page.evaluate!("navigator.clipboard.readText()")?, "joy dev") ? |e| TheElementsTextShouldBeOnTheClipboard(Str.inspect(e))
	} else {
		{}
	}

	browser.close!()?
	Ok({})
}
