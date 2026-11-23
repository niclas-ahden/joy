app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.2/BFCzMMp3DePaKT1sLy1m38p7qS5QB3okSVoFy6A1Y3Jf.tar.zst",
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
