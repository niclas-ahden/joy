# Hydration over elements with a DOM property named `content`: the lab's
# "content" page renders a <template>, whose children the parser moves into
# its `content` fragment, and a microdata <meta>, whose `content` is its
# attribute as a string. The claim must take both: a clean claim, equal to
# a client build, which builds a template's children as its own.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.32.0/3MnQnCrtfe6XS5qx58MnAGU6iWk8i1N24MYfoejcWeax.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.15.2/BFCzMMp3DePaKT1sLy1m38p7qS5QB3okSVoFy6A1Y3Jf.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.1/GXr8UJ7VDaJ8HYykmVYtTjLs7X4bZeE9YDTzAHoVXFJ9.tar.zst",
}

import spec.Assert
import Browser

main! = |_args| {
	# The page only gets data-booted once mount resolves, so a claim that
	# throws fails right here.
	{ browser, page } = Browser.open_page!("hydrate_lab/content", "#app[data-booted]")?

	Assert.eq(page.evaluate!("JSON.stringify(window.app.hydration())")?, "{\"claimed\":true,\"mismatch\":null}") ? |e| ClaimNotClean(Str.inspect(e))
	Assert.eq(page.evaluate!("window.labAgainstFresh().then((d) => JSON.stringify(d))")?, "[]") ? |e| ClaimedPageDiffersFromAClientBuild(Str.inspect(e))
	Assert.eq(page.evaluate!("String(document.querySelector('#app meta[itemprop=lab]').content)")?, "claimed") ? |e| MetaLostItsContent(Str.inspect(e))

	# One copy of the template's children, where a client build puts them,
	# and none left behind in the fragment the parser filled.
	Assert.eq(page.evaluate!(template_children)?, "1 0") ? |e| TemplateChildrenNotClaimedOnce(Str.inspect(e))

	browser.close!()?
	Ok({})
}

template_children : Str
template_children =
	\\(() => {
	\\  const t = document.querySelector('#app template.stamp');
	\\  return t.querySelectorAll('.in-template').length + ' ' + t.content.childNodes.length;
	\\})()
