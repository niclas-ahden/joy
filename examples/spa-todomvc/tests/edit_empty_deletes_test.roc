app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
}

import TodoPage
import playwright.Playwright exposing [assert!]

# Committing an emptied-out todo deletes it, per the TodoMVC spec
main! = |_args| {
	{ browser, page } = TodoPage.open!({})?

	TodoPage.add!(page, "First")?
	TodoPage.add!(page, "Second")?

	TodoPage.edit!(page, 1)?
	edit_input = "${TodoPage.row(1)} .edit"
	# Whitespace only, so the trim leaves nothing to keep
	page.find(edit_input).fill!("   ")?
	page.key_press!(edit_input, Enter, [])?
	assert!(page.find_all(".todo-list li").has_count(1)) ? |e| EmptiedTodoShouldBeDeleted(Str.inspect(e))
	assert!(page.find(TodoPage.label(1)).has_text("Second")) ? |e| TheOtherTodoShouldRemain(Str.inspect(e))

	browser.close!()
}
