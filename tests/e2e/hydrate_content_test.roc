# Hydration over elements with a DOM property named `content`: the lab's
# "content" page renders a <template>, whose children the parser moves into
# its `content` fragment, and a microdata <meta>, whose `content` is its
# attribute as a string. The claim must take both: a clean claim, equal to
# a client build, which builds a template's children as its own.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.28.0/AP9SGT1yrhCKcFxKcoA5tBkNCM6ibBjBxcQGMTb6krev.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.11.1/GJz6pEptEAmK2FqGnzJQUhF9cymdiV3vwETDdCDevAZ1.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.6.1/55UFmX5Ye5dNxWYzbzxQfsE54KTNwaoHNmYan163HbzB.tar.zst",
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
