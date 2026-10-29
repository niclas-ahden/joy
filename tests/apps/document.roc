app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.17.1/AcmwFzyfbsf5RALWNdX6cXw1cuuDXt96YfcysNqgFqoG.tar.zst",
	pf: platform "../../platform/main.roc",
}

import html.Html exposing [button, div, p, text]
import html.Attribute exposing [id, on_click, style]
import pf.Clipboard
import pf.DOM
import pf.Effect

# Fixture for DOM.set_title, DOM.scroll_to, DOM.on_document_click,
# Clipboard.write_text and Clipboard.write_text_of
# (tests/check_document.mjs and tests/e2e/document_test.roc). `init` names
# the first page, "Next" names the next one and scrolls to the top the way a
# page switch does, and both copy buttons show which of them the clipboard
# answered and what it said.
# The tests put HTML of their own around the root: elements carrying
# `data-pick`, whose clicks the app names, and a `#source` whose text the
# second copy button copies. The page is tall, with a second "Next" at its
# foot, so a browser test can click it from far down and see the page
# return to the top.

Model : { page : U64, copied : Str, picked : Str }

Msg : [UserClickedNext, UserClickedCopy, UserClickedCopyOfSource, UserClickedPageElement(Str), ClipboardAnswered(Str, Try({}, Clipboard.Problem))]

subscriptions = |_model| [DOM.on_document_click("data-pick", |value| UserClickedPageElement(value))]

init : Str -> (Model, List(Effect(Msg)))
init = |_| ({ page: 1, copied: "not yet", picked: "nothing" }, [DOM.set_title("Page 1")])

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserClickedNext => {
			page = model.page + 1
			({ ..model, page }, [DOM.set_title("Page ${page.to_str()}"), DOM.scroll_to({ x: 0, y: 0 })])
		}
		UserClickedCopy => (model, [Clipboard.write_text("roc build", |answer| ClipboardAnswered("the text", answer))])
		UserClickedCopyOfSource => (model, [Clipboard.write_text_of("#source", |answer| ClipboardAnswered("#source", answer))])
		UserClickedPageElement(picked) => ({ ..model, picked }, [])
		ClipboardAnswered(what, Ok({})) => ({ ..model, copied: "copied ${what}" }, [])
		ClipboardAnswered(what, Err(problem)) => ({ ..model, copied: "failed ${what}: ${Str.inspect(problem)}" }, [])
	}

view : Model -> Html(Msg)
view = |model|
	div(
		[],
		[
			p([id("page")], [text("page ${model.page.to_str()}")]),
			button([id("next"), on_click(UserClickedNext)], [text("Next")]),
			button([id("copy"), on_click(UserClickedCopy)], [text("Copy")]),
			p([id("copied")], [text(model.copied)]),
			button([id("copy-source"), on_click(UserClickedCopyOfSource)], [text("Copy the source")]),
			p([id("picked")], [text("picked: ${model.picked}")]),
			div([style([("height", "3000px")])], []),
			button([id("next-at-foot"), on_click(UserClickedNext)], [text("Next at the foot")]),
		],
	)
