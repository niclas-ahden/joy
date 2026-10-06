# A server that renders stale attributes: the lab's "stale" page
# (tests/apps/hydrate_lab/ssr.roc) has the count button disabled, with a
# class and a data attribute the client's first render does not have. The
# claim reports it and repairs every one of them, so the page ends up equal
# to a client build, and the button, which the client never disables,
# works. A stale `disabled` the claim left alone would disable it for good,
# since later renders only diff the attributes the view declares.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.10.0/ELCrvV4MsjnA4phYGXW3oLW2fH9y1imCxPkxhVnpW9jG.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.0/9ThTkhd7zrviwQpM3LvGd7pvzGhr4ZXNmWJV7pTJc9AJ.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open_page!("hydrate_lab/stale", "#app[data-booted]")?

	Assert.eq(page.evaluate!("String(window.app.hydration().mismatch)")?, "expected class=\"count\" on <button> but the server rendered class=\"count stale-class\"") ? |e| StaleClassNotReported(Str.inspect(e))
	Assert.eq(page.evaluate!("window.labAgainstFresh().then((d) => JSON.stringify(d))")?, "[]") ? |e| RepairedPageDiffersFromAClientBuild(Str.inspect(e))
	Assert.eq(page.evaluate!(button_state)?, "disabled=false data-stale=false class=count") ? |e| StaleAttributesSurvived(Str.inspect(e))

	# The button works, and stays enabled through renders.
	page.click!(".count")?
	page.click!(".count")?
	Assert.eq(page.evaluate!("document.querySelector('.echo').textContent")?, "Ann|First line\nsecond line|m|blue|yes|2") ? |e| CountNotCounted(Str.inspect(e))
	Assert.eq(page.evaluate!(button_state)?, "disabled=false data-stale=false class=count") ? |e| StaleAttributesCameBack(Str.inspect(e))

	browser.close!()?
	Ok({})
}

button_state : Str
button_state =
	\\(() => {
	\\  const b = document.querySelector('button.count');
	\\  return 'disabled=' + b.disabled + ' data-stale=' + b.hasAttribute('data-stale') + ' class=' + b.getAttribute('class');
	\\})()
