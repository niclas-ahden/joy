app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.1/GJz6pEptEAmK2FqGnzJQUhF9cymdiV3vwETDdCDevAZ1.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# The toggle-all checkbox mirrors the todos: checked exactly while every
# todo is completed, however that comes about
main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "First")?
	TodoPage.add!(page, "Second")?
	assert!(page.find(".toggle-all").is_unchecked()) ? |e| ShouldStartUnchecked(Str.inspect(e))

	page.find(TodoPage.toggle(1)).check!()?
	assert!(page.find(".toggle-all").is_unchecked()) ? |e| OneOfTwoIsNotAll(Str.inspect(e))

	page.find(TodoPage.toggle(2)).check!()?
	assert!(page.find(".toggle-all").is_checked()) ? |e| CompletingTheLastShouldCheckIt(Str.inspect(e))

	page.find(TodoPage.toggle(1)).uncheck!()?
	assert!(page.find(".toggle-all").is_unchecked()) ? |e| RevivingOneShouldUncheckIt(Str.inspect(e))

	# Destroying the only active todo leaves only completed ones
	TodoPage.destroy!(page, 1)?
	assert!(page.find(".toggle-all").is_checked()) ? |e| DestroyingTheActiveOneShouldCheckIt(Str.inspect(e))

	browser.close!()
}
