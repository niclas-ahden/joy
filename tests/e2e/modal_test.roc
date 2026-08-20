# Real-browser E2E: the modal example in Chromium. The fake DOM can only
# approximate <dialog> semantics, so this is exactly the coverage a real
# browser adds: showModal/close driven from update!, with visibility checked
# by the browser itself.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.7.0/BW5do1pddeCsifMZcgwV4fjYH5mdy9sNA4moigRTvQNg.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.3.0/2v2CV8CLXRJmQRvfoHtPngAUGgE8jL6DDgXbugZhFVf5.tar.zst",
}

import playwright.Playwright
import Support

main! = |_args| {
	{ browser, page } = Support.open!("modal", "#open")?

	# The dialog starts closed: its contents must not be visible.
	before = Playwright.is_visible!(page, "#prompt")?
	if before {
		Err(DialogOpenBeforeClick)?
	}

	# "Delete everything" -> update! calls DOM.show_modal!("#confirm").
	Playwright.click!(page, "#open")?
	Playwright.wait_for!(page, "#prompt", Visible)?

	# "Yes, delete" -> update! closes the dialog and counts the confirm.
	Playwright.click!(page, "#yes")?
	Playwright.wait_for!(page, "#prompt", Hidden)?

	Support.expect_text!(page, "#counts", "opened 1, confirmed 1", |got| ModalFlowWrong(got))?

	Playwright.close!(browser)?
	Ok({})
}
