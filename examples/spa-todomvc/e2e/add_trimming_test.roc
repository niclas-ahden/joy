app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.2/BFCzMMp3DePaKT1sLy1m38p7qS5QB3okSVoFy6A1Y3Jf.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]
import spec.Assert

main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	# has_text normalizes whitespace on both sides, so it cannot see a
	# missing trim. Read the exact text instead.
	TodoPage.add!(page, "  padded  ")?
	Assert.eq(page.find(TodoPage.label(1)).text!()?, "padded") ? |e| TitleShouldBeTrimmed(Str.inspect(e))

	# Whitespace only trims down to nothing, so nothing is added
	TodoPage.add!(page, "   ")?
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| BlankTitleShouldAddNothing(Str.inspect(e))

	browser.close!()
}
