app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
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
