## Change the URL, and follow it as it changes.
##
## An app with several pages uses these together, for links that open a page
## of the app without loading anything, with Back and Forward working:
##
## ```roc
## subscriptions = |_model| [
##     Navigation.on_link_click(|url| UserClickedLink(url)),
##     Navigation.on_url_change(|url| UrlChanged(url)),
## ]
##
## update = |model, msg|
##     match msg {
##         UserClickedLink(url) =>
##             (model, [Navigation.push_url(url)])
##
##         UrlChanged(url) => ({ ..model, url }, [])
##     }
## ```
##
## [Navigation.on_link_click] hands you the clicks on your app's links, and
## [Navigation.on_url_change] tells you each time the URL changes, whatever
## changed it.
##
## ## Three ways to change the URL
##
## | | Loads a page | Adds a step for Back |
## |---|---|---|
## | [Navigation.replace_url] | no | no |
## | [Navigation.push_url] | no | yes |
## | [Navigation.navigate] | yes | yes |
##
## The guide has [a navigation example](../../#example-navigation) to try.
import Effect
import Sub
import Wire

Navigation := [].{

	## Go to a URL by loading it, as a plain link does. Your app starts over, so
	## the model is gone.
	##
	## ```roc
	## Navigation.navigate("/login")
	## ```
	navigate : Str -> Effect(msg)
	navigate = |url| Effect.send("joy/navigation/navigate", Wire.writer({}).str(url).done())

	## Change the URL without loading a page, and add a step to the history, so
	## Back returns to the URL before.
	##
	## ```roc
	## UserClickedLink(url) => (model, [Navigation.push_url(url)])
	## ```
	##
	## Your app hears of the new URL through [Navigation.on_url_change], the same way it
	## hears of Back and Forward. So the code that opens the page a URL names is
	## written once, there.
	##
	## The page is then shown from the top, or from the element the URL's
	## `#fragment` names, as a page the browser loads is. Pushing the URL that is
	## already showing does nothing.
	push_url : Str -> Effect(msg)
	push_url = |url| Effect.send("joy/navigation/push_url", Wire.writer({}).str(url).done())

	## Change the URL in place: no page load, no step in the history, and the page
	## stays scrolled where it is.
	##
	## ```roc
	## Navigation.replace_url("?q=${model.query}")
	## ```
	##
	## It is for things like keeping `?q=...` in step with a search box, where
	## Back should not walk through every key press. Your app hears of it through
	## [Navigation.on_url_change], unless the URL is the one already showing.
	replace_url : Str -> Effect(msg)
	replace_url = |url| Effect.send("joy/navigation/replace_url", Wire.writer({}).str(url).done())

	## A message each time the page's URL changes. It carries the whole address,
	## like `https://example.com/notes/3?sort=new#top`.
	##
	## ```roc
	## Navigation.on_url_change(|url| UrlChanged(url))
	## ```
	##
	## It hears all of these:
	##
	## - Back and Forward.
	## - [Navigation.push_url] and [Navigation.replace_url].
	## - A click on a link to a `#fragment` of the page, which the browser follows
	##   without loading anything.
	##
	## An app with several pages opens the page an address names here, and nowhere
	## else.
	on_url_change : (Str -> msg) -> Sub(msg)
	on_url_change = |on_change|
		Sub.listen("joy/navigation/url_changed", [], |event| on_change(Wire.reader(event).str().map_ok(|(url, _)| url) ?? ""))

	## A message each time the user clicks a link of your site inside your app,
	## with the link's whole address. Your app then decides what happens, and
	## [Navigation.push_url] with that address goes there without loading a page.
	##
	## ```roc
	## Navigation.on_link_click(|url| UserClickedLink(url))
	## ```
	##
	## Some clicks stay the browser's: one with Ctrl, Shift, Alt or Meta held, a
	## link that opens in another tab or downloads, and a link to another site.
	##
	## Without this subscription every link loads its page, as links do.
	on_link_click : (Str -> msg) -> Sub(msg)
	on_link_click = |on_click|
		Sub.listen("joy/navigation/link_clicks", [], |event| on_click(Wire.reader(event).str().map_ok(|(url, _)| url) ?? ""))
}

# Each helper is one effect. Pin its id and argument so a helper can
# never quietly produce its sibling (push as replace).

sent : Effect(msg) -> Try((Str, Str), [NotSent])
sent = |effect|
	match effect {
		Send(_, args) => Wire.reader(args).str().map_ok(|(value, _)| (effect.identity().id, value)).map_err(|_| NotSent)
		_ => Err(NotSent)
	}

expect sent(Navigation.navigate("/login")) == Ok(("joy/navigation/navigate", "/login"))
expect sent(Navigation.push_url("?page=2")) == Ok(("joy/navigation/push_url", "?page=2"))
expect sent(Navigation.replace_url("?q=hats")) == Ok(("joy/navigation/replace_url", "?q=hats"))

expect {
	sub = Navigation.on_url_change(|url| "now:${url}")
	sub.identity().id == "joy/navigation/url_changed" and sub.deliver(Wire.writer({}).str("https://example.com/diary?q=1").done()) == "now:https://example.com/diary?q=1"
}

expect {
	sub = Navigation.on_link_click(|url| "clicked:${url}")
	sub.identity().id == "joy/navigation/link_clicks" and sub.deliver(Wire.writer({}).str("https://example.com/about").done()) == "clicked:https://example.com/about"
}
