# Real-browser E2E: two apps on one page. Both use the same debounce key and
# selectors and get the same file id, and each keeps its own. The object URLs are
# the browser's, so reading one back shows whose file it holds.
app [main!] {
	pf: platform "https://github.com/niclas-ahden/basic-cli/releases/download/0.30.0/6XAUy48Jp34GANurMrMf74DtF7NdpkhnqFLHE4gHNzJy.tar.zst",
	playwright: "https://github.com/niclas-ahden/roc-playwright/releases/download/0.13.1/AWahhV9oKjtqpZNTG5mUK5i86Fy1Lwssrg6yeDG52Bvy.tar.zst",
	spec: "https://github.com/niclas-ahden/roc-spec/releases/download/0.7.0/BGjQKbG9U3V8cH6mRbypUAFVqFoVEu6n9bsA3QmFL1f4.tar.zst",
}

import playwright.Playwright exposing [assert!]
import spec.Assert
import Browser

main! = |_args| {
	{ browser, page } = Browser.open!("many_apps", "#arm")?

	_ = page.evaluate!(
		\\(async () => {
		\\  const { mount } = await import(new URL('./runtime.js', location.href).href);
		\\  const root = document.createElement('div');
		\\  root.id = 'second';
		\\  document.body.append(root);
		\\  window.second = await mount({ wasm: new URL('./app.wasm', location.href).href, root, flags: 'grab' });
		\\  return 'mounted';
		\\})()
	)?
	assert!(page.find("#second #arm").is_visible())?

	# The same key, armed in both, fires in both.
	page.find("#app #arm").click!()?
	page.find("#second #arm").click!()?
	assert!(page.find("#app #fired").has_text("1"))?
	assert!(page.find("#second #fired").has_text("1"))?

	# Both files get the id 1, and each app's URL holds its own.
	pick!(page, "#app", "from the first")?
	pick!(page, "#second", "from the second")?
	page.find("#app #ask").click!()?
	page.find("#second #ask").click!()?
	assert!(page.find("#app #url").contains_text("blob:"))?
	assert!(page.find("#second #url").contains_text("blob:"))?
	Assert.eq(read_url!(page, "#app")?, "from the first") ? |e| FirstAppShouldGetItsOwnFile(Str.inspect(e))
	Assert.eq(read_url!(page, "#second")?, "from the second") ? |e| SecondAppShouldGetItsOwnFile(Str.inspect(e))

	# A selector finds the app's own element, and a dialog elsewhere on the page.
	_ = page.evaluate!(
		\\(() => {
		\\  HTMLMediaElement.prototype.play = function () { window.played = this.closest('#app, #second').id; return Promise.resolve(); };
		\\  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: async (text) => { window.copied = text; } } });
		\\  document.querySelector('#second #quote').textContent = 'quote of the second';
		\\  const dialog = document.createElement('dialog');
		\\  dialog.id = 'page-dialog';
		\\  document.body.append(dialog);
		\\  return 'set';
		\\})()
	)?
	page.find("#second #focus").click!()?
	same!(page, "document.activeElement.closest('#app, #second').id", "second")?
	press!(page, "#second #open")?
	same!(page, "String(document.querySelector('#second #dialog').open)", "true")?
	same!(page, "String(document.querySelector('#app #dialog').open)", "false")?
	_ = page.evaluate!("(document.querySelector('#app #dialog').showModal(), 'open')")?
	press!(page, "#second #shut")?
	same!(page, "String(document.querySelector('#second #dialog').open)", "false")?
	same!(page, "String(document.querySelector('#app #dialog').open)", "true")?
	_ = page.evaluate!("(document.querySelector('#app #dialog').close(), 'closed')")?
	press!(page, "#second #play")?
	same!(page, "window.played", "second")?
	press!(page, "#second #copy")?
	same!(page, "window.copied", "quote of the second")?
	press!(page, "#second #open-page-dialog")?
	same!(page, "String(document.querySelector('#page-dialog').open)", "true")?
	_ = page.evaluate!("(document.querySelector('#page-dialog').close(), 'closed')")?

	# The second app holds on to the space key, except in a field that is not its own.
	page.key_type!("#app #name", "a b")?
	assert!(page.find("#app #name").has_value("a b"))?
	assert!(page.find("#second #keys").has_text("1"))?
	page.key_type!("#second #name", "c d")?
	assert!(page.find("#second #name").has_value("cd"))?
	assert!(page.find("#second #keys").has_text("2"))?

	# Unmounting one leaves the other's debounce and its URL.
	page.find("#app #arm").click!()?
	page.find("#second #arm").click!()?
	_ = page.evaluate!("(window.second.unmount(), 'unmounted')")?
	assert!(page.find("#app #fired").has_text("2"))?
	Assert.eq(read_url!(page, "#app")?, "from the first") ? |e| FirstUrlShouldOutliveTheSecondApp(Str.inspect(e))

	browser.close!()
}

# A click from the page, which a modal dialog's inert background would not take.
press! = |page, selector| {
	_ = page.evaluate!("new Promise((done) => { document.querySelector('${selector}').click(); setTimeout(() => done('pressed'), 50) })")?
	Ok({})
}

same! = |page, expression, want| {
	Assert.eq(page.evaluate!(expression)?, want) ? |e| NotTheAppsOwn(Str.inspect({ expression, e }))
	Ok({})
}

pick! = |page, root, content| {
	_ = page.evaluate!(
		\\(() => {
		\\  const input = document.querySelector('${root} #upload');
		\\  const picked = new DataTransfer();
		\\  picked.items.add(new File(['${content}'], 'memo.txt'));
		\\  input.files = picked.files;
		\\  input.dispatchEvent(new Event('change', { bubbles: true }));
		\\  return 'picked';
		\\})()
	)?
	Ok({})
}

read_url! = |page, root|
	page.evaluate!("fetch(document.querySelector('${root} #url').textContent).then((r) => r.text())")
