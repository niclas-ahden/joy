# Real-browser E2E: the app of the guide's Your first app, as it is written
# there, in a project of its own. The app and the page come from the guide's
# own text, ./joy dev runs them, and saving the file keeps the count, as Joy on
# your machine says it does.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.31.0/Ff3fkK1TjYTVxMj9V21FP24ojTJXYk314Fbo1whBZ6Yf.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.14.0/83Dw68fzvXTQMbcZXupMDB3YiEP6pS6YgKxuTDjuMSAw.tar.zst",
}

import pf.Env
import pf.Path
import playwright.Playwright exposing [assert!]
import HotDev

main! = |_args| {
	if !HotDev.has_cli!() {
		return Ok({})
	}
	opt = Env.var_str!("JOY_OPT") ?? "speed"
	dir = "build/${opt}/guide_first_app"
	HotDev.fresh!(dir)?
	Path.utf8("${dir}/client").create_all!()?
	Path.utf8("${dir}/public").create_all!()?

	# The topic's counter.roc, on this checkout's platform.
	blocks = samples!("FirstApp", "counter.roc")?
	source = Str.join_with(blocks, "\n\n")
	release = "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst"
	if !source.contains(release) {
		return Err(TheGuideNamesNoRelease(source))
	}
	Path.utf8("${dir}/client/counter.roc").write_utf8!(source.replace_first(release, "../../../../platform/main.roc"))?

	# The page the topic points at in Flags, naming this bundle.
	page_html = samples!("Flags", "public/index.html")?.first()?
	if !page_html.contains("data-joy-bundle=\"app\"") {
		return Err(TheGuidesPageNamesNoBundle(page_html))
	}
	Path.utf8("${dir}/public/index.html").write_utf8!(page_html.replace_first("data-joy-bundle=\"app\"", "data-joy-bundle=\"counter\""))?

	started = HotDev.run!(dir, "", "8777")?
	{ page, url, .. } = started
	HotDev.open!(page, "${url}/", "[data-joy-bundle=counter] button")?
	page.find("[data-joy-bundle=counter] button:nth-of-type(2)").click!()?
	page.find("[data-joy-bundle=counter] button:nth-of-type(2)").click!()?
	assert!(page.find("[data-joy-bundle=counter]").has_text("-2+"))?

	# "The page takes the change as you save, no refresh needed."
	HotDev.mark!(page)?
	HotDev.edit!("${dir}/client/counter.roc", "[text(\"+\")]", "[text(\"add\")]")?
	HotDev.shows!(page, "[data-joy-bundle=counter]", "-2add")?
	HotDev.same_page!(page)?

	HotDev.stop!(started)
}

## The text of each of a topic's code blocks labelled `file`.
samples! = |topic, file| {
	text = Path.utf8("guide/Topic/${topic}.roc").read_utf8!()?
	found = text.split_on("Doc.code(").drop_first(1).keep_if(|block| block.contains("\"${file}\",")).map(
		|block| {
			lines = block.split_on("\n").map(Str.trim).keep_if(|line| line.starts_with("\\\\")).map(|line| line.drop_prefix("\\\\").replace_each("\\$", "$"))
			Str.join_with(lines, "\n")
		},
	)
	if found.is_empty() {
		Err(NoSuchSample({ topic, file }))
	} else {
		Ok(found)
	}
}
