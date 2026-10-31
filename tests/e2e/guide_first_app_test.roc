# Real-browser E2E: the guide's Your first app, followed as it is written. The app
# and the page come from the guide's own text, ./joy dev runs them, and saving the
# file keeps the count, as the topic says it does.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
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

	# The topic's two blocks of client/counter.roc, on this checkout's platform.
	blocks = samples!("FirstApp", "client/counter.roc")?
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
	HotDev.open!(page, "${url}/", "#increment")?
	page.find("#increment").click!()?
	page.find("#increment").click!()?
	assert!(page.find("[data-joy-bundle=counter]").has_text("+2-"))?

	# "Save client/counter.roc and the open page takes the new build without a
	# reload: the count you clicked up to stays."
	HotDev.mark!(page)?
	HotDev.edit!("${dir}/client/counter.roc", "[text(\"+\")]", "[text(\"add\")]")?
	HotDev.shows!(page, "[data-joy-bundle=counter]", "add2-")?
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
