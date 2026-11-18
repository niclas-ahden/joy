# Markup the parser rewrites: the lab's "bare" page puts table rows straight
# in a <table>, which the HTML parser wraps in a <tbody>, so the server's
# page never matches the view however right the server is. The claim says so
# with a hint at the fix, and repairs the table into the client's shape.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.1/3tP6sNB4zffazkHJkdzQTxcme4m7x2Fk6fzL7zFKj4C6.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open_page!("hydrate_lab/bare", "#app[data-booted]")?

	Assert.eq(page.evaluate!("String(window.app.hydration().mismatch)")?, "expected <tr> but the server rendered <tbody> (the HTML parser puts a <tr> that sits directly in a <table> inside a <tbody>, so give the rows a tbody of their own)") ? |e| TbodyNotExplained(Str.inspect(e))
	Assert.eq(page.evaluate!("window.labAgainstFresh().then((d) => JSON.stringify(d))")?, "[]") ? |e| RepairedPageDiffersFromAClientBuild(Str.inspect(e))
	assert!(page.find_all("table.rows > tr").has_count(2))?

	browser.close!()?
	Ok({})
}
