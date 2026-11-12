app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.14.0/83Dw68fzvXTQMbcZXupMDB3YiEP6pS6YgKxuTDjuMSAw.tar.zst",
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
