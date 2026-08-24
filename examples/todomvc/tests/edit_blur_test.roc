app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.24.0/2mx1EsQx1HEG7HdbW2CwUpexvmJZW4nSCpjbur5GXyRe.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.8.0/9boAetfXPFWCmMg5uavT1juSYFRw9zaGsWcfs4qspXde.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# Clicking away from an edit commits it, like Enter would
main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "Original")?

	TodoPage.edit!(page, 1)?
	page.find("${TodoPage.row(1)} .edit").fill!("Committed by blur")?
	page.find("h1").click!()?
	assert!(page.find(TodoPage.label(1)).has_text("Committed by blur")) ? |e| BlurShouldCommit(Str.inspect(e))
	assert!(page.find_all(".todo-list li.editing").is_empty()) ? |e| EditingShouldEnd(Str.inspect(e))

	browser.close!()
}
