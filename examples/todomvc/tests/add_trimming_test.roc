app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.1/GJz6pEptEAmK2FqGnzJQUhF9cymdiV3vwETDdCDevAZ1.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.1/55UFmX5Ye5dNxWYzbzxQfsE54KTNwaoHNmYan163HbzB.tar.zst",
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
