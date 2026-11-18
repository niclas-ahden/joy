import html.Html exposing [a, code, div, h1, h2, li, p, table, tbody, td, text, th, thead, tr, ul]
import html.Attribute exposing [class, href]
import /Doc

## The topic "Custom effects".
CustomEffects := [].{
	body : Doc.Body
	body = [
		p([class("eyebrow")], [text("Reference")]),
		h1([], [text("Custom effects")]),
		p(
			[class("lead")],
			[
				text("The platform's modules cover a lot of the browser, and not all of it. When you need something they lack, you write a custom effect: a Roc function your app calls, and the JavaScript that Joy runs for it."),
			],
		),
		p(
			[],
			[
				text("This topic builds three. The first asks the browser a question and gets an answer. The second takes arguments and can fail. The third is a subscription."),
			],
		),
		h2([], [text("Where they live")]),
		p(
			[],
			[
				text("Your custom effects are a small package inside "),
				c("client/"),
				text(", in a folder called "),
				c("effects"),
				text(". Each one is two files with the same name: the Roc your app calls, and the JavaScript the browser runs."),
			],
		),
		Doc.code(
			Text,
			"",
			\\client/
			\\    main.roc          your app
			\\    effects/
			\\        main.roc      the package
			\\        Locale.roc    what your app calls
			\\        Locale.js     what the browser does
			\\        Share.roc
			\\        Share.js
			\\        Network.roc
			\\        Network.js
		),
		p(
			[],
			[
				text("The package lists its modules and names the platform. A new module needs its name in that list. The platform line is the one your app has:"),
			],
		),
		Doc.code(
			Roc,
			"client/effects/main.roc",
			\\package [Locale, Share, Network] {
			\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
			\\}
		),
		p(
			[],
			[
				text("Both have to name the same platform, or Roc stops the build and says which two files disagree. If yours is a path to a checkout, it is written from the file it is in, so it is one "),
				c("../"),
				text(" longer here than in your app."),
			],
		),
		p(
			[],
			[
				text("Your app then names the package in its header. The app's file is "),
				c("client/main.roc"),
				text(" here, and "),
				c("client/app.roc"),
				text(" in a project from a template:"),
			],
		),
		Doc.code(
			Roc,
			"client/main.roc",
			\\app [Model, Msg, init, update, view, subscriptions] {
			\\    pf: platform "https://github.com/niclas-ahden/joy/releases/download/VERSION/HASH.tar.zst",
			\\    html: "https://github.com/growthagent/joy-html/releases/download/0.18.0-rc2/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
			\\    effects: "effects/main.roc",
			\\}
		),
		h2([], [text("The Roc half")]),
		p(
			[],
			[
				text("The first custom effect asks the browser which language and time zone it is set to. "),
				c("Locale.roc"),
				text(" is an ordinary module. Its function returns an effect, like the functions of the platform's own modules, and it makes that effect with "),
				c("Effect.call"),
				text(":"),
			],
		),
		Doc.code(
			Roc,
			"client/effects/Locale.roc",
			\\import pf.Effect
			\\import pf.Wire
			\\
			\\Locale := [].{
			\\    Info : { language : Str, time_zone : Str }
			\\
			\\    get : (Try(Info, Str) -> msg) -> Effect(msg)
			\\    get = |to_msg| Effect.call("my_app/locale_get", [], |reply| to_msg(info(reply)))
			\\}
		),
		p(
			[],
			[
				c("Effect.call"),
				text(" takes three things: the id of the custom effect, its arguments, and what to do with the reply. The id is how the two halves find each other. This one has no arguments, so they are "),
				c("[]"),
				text("."),
			],
		),
		p(
			[],
			[
				text("The reply arrives as bytes, and "),
				c("info"),
				text(" turns them into the record. "),
				c("Effect.reply"),
				text(" gives the answer, or the failure if the JavaScript threw. "),
				c("Wire.reader"),
				text(" then reads the answer one value at a time. Each read gives the value and a reader for what comes after it. A read can fail, and "),
				c("Wire.explain"),
				text(" explains why it happened:"),
			],
		),
		Doc.code(
			Roc,
			"client/effects/Locale.roc",
			\\info : List(U8) -> Try(Locale.Info, Str)
			\\info = |reply| {
			\\    answer = Effect.reply(reply) ? |EffectFailed({ name, message })| "\${name}: \${message}"
			\\    (language, rest) = Wire.reader(answer).str() ? Wire.explain
			\\    (time_zone, _) = rest.str() ? Wire.explain
			\\    Ok({ language, time_zone })
			\\}
		),
		h2([], [text("The JavaScript half")]),
		p(
			[],
			[
				c("Locale.js"),
				text(" sits beside "),
				c("Locale.roc"),
				text(" and that is how "),
				c("./joy"),
				text(" finds it. It defines the custom effect under the same id, and answers with the two strings in the order the Roc half reads them:"),
			],
		),
		Doc.code(
			Js,
			"client/effects/Locale.js",
			\\//// effect my_app/locale_get
			\\defineEffect('my_app/locale_get', () => {
			\\  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
			\\  return new WireWriter().str(navigator.language).str(timeZone);
			\\});
		),
		ul(
			[],
			[
				li([], [text("The line that starts with "), c("////"), text(" opens a section and says what the code under it defines. A file can hold several sections.")]),
				li([], [c("defineEffect"), text(" takes the id and the function to run.")]),
				li([], [text("The function answers by returning a "), c("WireWriter"), text(". Returning nothing answers with no bytes.")]),
				li([], [text("The file's code can use "), c("defineEffect"), text(", "), c("defineSubscription"), text(", "), c("WireWriter"), text(" and whatever the browser offers.")]),
			],
		),
		h2([], [text("Using it")]),
		p([], [text("From here on it is an effect like any other. Import the module, return its effect, here from "), c("init"), text(", and handle the message it comes back as in "), c("update"), text(":")]),
		Doc.code(
			Roc,
			"client/main.roc",
			\\import effects.Locale
			\\
			\\init : Str -> (Model, List(Effect(Msg)))
			\\init = |_| ({ locale: "", network: Online, note: "" }, [Locale.get(|result| GotLocale(result))])
			\\
			\\GotLocale(Ok(info)) => ({ ..model, locale: "\${info.language}, \${info.time_zone}" }, [])
			\\GotLocale(Err(why)) => ({ ..model, locale: why }, [])
		),
		p(
			[],
			[
				c("./joy dev"),
				text(" watches both files. Save "),
				c("Locale.js"),
				text(" and the page starts over with the new JavaScript."),
			],
		),
		p(
			[],
			[
				text("Any module of the app imports the package the same way, a page's module too. An effect returned from "),
				c("init"),
				text(" runs after the first render, so its JavaScript finds the page's elements."),
			],
		),
		h2([], [text("Arguments and failures")]),
		p(
			[],
			[
				text("The second custom effect opens the browser's share sheet. It sends a title and a link to the JavaScript, and it can fail: the browser may have no share sheet, or the person may close it. "),
				c("Wire.writer"),
				text(" writes the arguments one after another:"),
			],
		),
		Doc.code(
			Roc,
			"client/effects/Share.roc",
			\\Share := [].{
			\\    Problem : [Cancelled, Unavailable, Other(Str)]
			\\
			\\    link : { title : Str, url : Str }, (Try({}, Problem) -> msg) -> Effect(msg)
			\\    link = |{ title, url }, to_msg|
			\\        Effect.call(
			\\            "my_app/share_link",
			\\            Wire.writer({}).str(title).str(url).done(),
			\\            |reply| to_msg(outcome(reply)),
			\\        )
			\\}
		),
		p(
			[],
			[
				text("The JavaScript reads them from "),
				c("args"),
				text(" in the same order. The function can be "),
				c("async"),
				text(", and the reply goes out when it finishes:"),
			],
		),
		Doc.code(
			Js,
			"client/effects/Share.js",
			\\//// effect my_app/share_link
			\\defineEffect('my_app/share_link', async (args) => {
			\\  const title = args.str();
			\\  const url = args.str();
			\\  if (!navigator.share) {
			\\    throw new DOMException('This browser has no share sheet', 'NotSupportedError');
			\\  }
			\\  await navigator.share({ title, url });
			\\});
		),
		p(
			[],
			[
				text("What the function throws, or what its promise rejects with, reaches your app as "),
				c("EffectFailed"),
				text(" with the error's name and message. The name is how you tell one failure from another. For a failure of your own, give an error a name before you throw it, "),
				c("error.name = 'NothingToShare'"),
				text(", and match that name in Roc. The browser rejects with "),
				c("AbortError"),
				text(" when the person closes the sheet:"),
			],
		),
		Doc.code(
			Roc,
			"client/effects/Share.roc",
			\\outcome : List(U8) -> Try({}, Share.Problem)
			\\outcome = |reply|
			\\    match Effect.reply(reply) {
			\\        Ok(_) => Ok({})
			\\        Err(EffectFailed({ name: "AbortError", .. })) => Err(Cancelled)
			\\        Err(EffectFailed({ name: "NotSupportedError", .. })) => Err(Unavailable)
			\\        Err(EffectFailed({ message, .. })) => Err(Other(message))
			\\    }
		),
		p([], [text("Your app gets a result it can match on:")]),
		Doc.code(
			Roc,
			"client/main.roc",
			\\UserClickedShare =>
			\\    (model, [Share.link({ title: "Joy", url: "https://github.com/niclas-ahden/joy" }, |result| ShareEnded(result))])
			\\
			\\ShareEnded(Ok({})) => ({ ..model, note: "Shared" }, [])
			\\ShareEnded(Err(Cancelled)) => ({ ..model, note: "Not shared" }, [])
			\\ShareEnded(Err(Unavailable)) => ({ ..model, note: "This browser has no share sheet" }, [])
			\\ShareEnded(Err(Other(message))) => ({ ..model, note: message }, [])
		),
		h2([], [text("Values in and out")]),
		p(
			[],
			[
				text("The two halves pass values as bytes, and "),
				c("Wire"),
				text(" writes and reads them. The method has the same name on both sides:"),
			],
		),
		div(
			[class("table-wrap")],
			[
				table(
					[],
					[
						thead([], [tr([], [th([], [text("Roc type")]), th([], [text("Method")]), th([], [text("In JavaScript")])])]),
						tbody(
							[],
							[
								tr([], [td([], [c("Str")]), td([], [c("str")]), td([], [text("a string")])]),
								tr([], [td([], [c("Bool")]), td([], [c("bool")]), td([], [text("true or false")])]),
								tr([], [td([], [c("U8"), text(", "), c("U16"), text(", "), c("U32")]), td([], [c("u8"), text(", "), c("u16"), text(", "), c("u32")]), td([], [text("a number")])]),
								tr([], [td([], [c("U64"), text(", "), c("I64")]), td([], [c("u64"), text(", "), c("i64")]), td([], [text("a whole number")])]),
								tr([], [td([], [c("F64")]), td([], [c("f64")]), td([], [text("a number")])]),
								tr([], [td([], [c("List(U8)")]), td([], [c("bytes")]), td([], [text("a Uint8Array")])]),
							],
						),
					],
				),
			],
		),
		p(
			[],
			[
				text("There are no names and no JSON in between: a record goes field by field, and a list as its length and then its items. The two halves agree on the order the way a function and its caller agree on its arguments."),
			],
		),
		p(
			[],
			[
				text("Each value carries its kind, so most disagreements are caught. Reading a "),
				c("u32"),
				text(" where the other half wrote a string is an error on both sides, and so is reading past the end. In Roc it is an "),
				c("Err"),
				text(" that "),
				c("Wire.explain"),
				text(" puts in words, like \"Value 2 is a Bool, where the Roc reads a Str\". In JavaScript it throws, which fails the call with the same kind of message. JavaScript also refuses a number that does not fit, like "),
				c("u32(-1)"),
				text(", and the console says when an effect leaves some of its arguments unread. What is not caught is two values of the same kind in the wrong order, a width and a height say, so look at the page once after you change a pair."),
			],
		),
		h2([], [text("An effect with no answer")]),
		p(
			[],
			[
				text("When there is nothing to hear back, use "),
				c("Effect.send(id, args)"),
				text(". It takes no function for a reply, and its JavaScript returns nothing. A failure there has nowhere to go but the browser's console."),
			],
		),
		h2([], [text("Subscriptions")]),
		p(
			[],
			[
				text("Something that keeps happening is a "),
				a([href("#subscriptions")], [text("subscription")]),
				text(". The third custom effect hears the browser go offline and come back. Its Roc half uses "),
				c("Sub.listen"),
				text(", which takes the id, arguments, and what to do with each event:"),
			],
		),
		Doc.code(
			Roc,
			"client/effects/Network.roc",
			\\import pf.Sub
			\\import pf.Wire
			\\
			\\Network := [].{
			\\    Status : [Online, Offline]
			\\
			\\    on_change : (Status -> msg) -> Sub(msg)
			\\    on_change = |to_msg| Sub.listen("my_app/network_changes", [], |event| to_msg(status(event)))
			\\}
			\\
			\\status : List(U8) -> Network.Status
			\\status = |event| {
			\\    online = Wire.reader(event).bool().map_ok(|(is_online, _)| is_online) ?? False
			\\    if (online) Online else Offline
			\\}
		),
		p(
			[],
			[
				text("Its JavaScript is a section that starts with "),
				c("//// subscription"),
				text(" and calls "),
				c("defineSubscription"),
				text(". The function starts listening, calls "),
				c("emit"),
				text(" for each event, and returns a function that stops. Joy calls that one when the subscription leaves your app's list. "),
				c("args"),
				text(" holds what "),
				c("Sub.listen"),
				text(" was given, here nothing. If the JavaScript throws, the console says so and the app goes on:"),
			],
		),
		Doc.code(
			Js,
			"client/effects/Network.js",
			\\//// subscription my_app/network_changes
			\\defineSubscription('my_app/network_changes', (args, host, emit) => {
			\\  const tell = () => emit(new WireWriter().bool(navigator.onLine));
			\\  addEventListener('online', tell);
			\\  addEventListener('offline', tell);
			\\  return () => {
			\\    removeEventListener('online', tell);
			\\    removeEventListener('offline', tell);
			\\  };
			\\});
		),
		p(
			[],
			[
				c("host"),
				text(" is what the runtime lends the JavaScript of an effect or a subscription, as its second argument. "),
				c("host.root()"),
				text(" is the element the app is mounted on, and "),
				c("host.element(selector)"),
				text(" finds an element inside it. When several apps share a page they run the same JavaScript, so what a custom effect keeps between calls goes in "),
				c("host.own(name, make)"),
				text(", which makes it once for each app. A variable at the top of the file would be shared by all of them."),
			],
		),
		p([], [text("Your app subscribes to it:")]),
		Doc.code(
			Roc,
			"client/main.roc",
			\\import effects.Network
			\\
			\\subscriptions : Model -> List(Sub(Msg))
			\\subscriptions = |_model| [Network.on_change(|status| NetworkChanged(status))]
		),
		h2([], [text("Sharing code in a file")]),
		p(
			[],
			[
				text("Code above the first "),
				c("////"),
				text(" line of a file is shared by every section in it. That is the place for a function two custom effects both use. A section cannot use what another section defines: a build leaves out the sections your app does not use, and their code with them."),
			],
		),
		h2([], [text("Using a JavaScript library")]),
		p(
			[],
			[
				text("You can't use an "),
				c("import"),
				text(" line in your file, because Joy copies your code into its own runtime. The build tells you if you try. Load the library inside the custom effect instead, with "),
				c("import()"),
				text(". The browser fetches it the first time and keeps it:"),
			],
		),
		Doc.code(
			Js,
			"client/effects/Confetti.js",
			\\//// effect my_app/confetti_burst
			\\defineEffect('my_app/confetti_burst', async (args) => {
			\\  const { default: confetti } = await import('https://cdn.jsdelivr.net/npm/canvas-confetti@1.9.3/+esm');
			\\  confetti({ particleCount: args.u32() });
			\\});
		),
		p(
			[],
			[
				text("A library a "),
				c("<script>"),
				text(" tag already put on the page works as well. Its global is there for the custom effect to use."),
			],
		),
		h2([], [text("Ids")]),
		p(
			[],
			[
				text("An id joins a call in Roc to its JavaScript. You write it as a string, and the compiler holds you to that: "),
				c("Effect.call"),
				text(", "),
				c("Effect.send"),
				text(" and "),
				c("Sub.listen"),
				text(" take an id only as a string literal. One put together while the app runs does not compile."),
			],
		),
		ul(
			[],
			[
				li([], [text("Start it with a name of your own, like "), c("my_app/"), text(". Ids that start with "), c("joy/"), text(" are Joy's.")]),
				li([], [text("Use letters, digits and "), c("_ - . /"), text(" in it.")]),
				li([], [text("To give an id a name and use it in several places, annotate the name as "), c("Effect.Id"), text(", or "), c("Sub.Id"), text(" for a subscription.")]),
			],
		),
		p(
			[],
			[
				text("Since every id is written in the source, roc's compiled app holds exactly the ones it uses. "),
				c("./joy build"),
				text(" reads them from there, ships only those custom effects, and checks each one. An id that no JavaScript defines fails the build, and the report says where and what you may have meant:"),
			],
		),
		Doc.code(
			Text,
			"",
			\\── ✗ custom effect without javascript ──────────── client/effects/Share.roc:15:5
			\\
			\\No JavaScript defines the custom effect with this id:
			\\
			\\    "my_app/share_lnk",
			\\     ^^^^^^^^^^^^^^^^
			\\
			\\Did you mean this one?
			\\
			\\    my_app/share_link
		),
		h2([], [text("More than one bundle")]),
		p(
			[],
			[
				text("Every bundle that uses your custom effects names the package in its header. A path is written from the bundle's own file, so from "),
				c("client/admin/main.roc"),
				text(" it is "),
				c("effects: \"../effects/main.roc\""),
				text("."),
			],
		),
		h2([], [text("Ports or custom effects?")]),
		p(
			[],
			[
				c("pf.Port"),
				text(" passes strings between your app and JavaScript that lives on the page, outside your app. Use it when your app needs to talk to a script that's already there."),
			],
		),
		p(
			[],
			[
				text("Use a custom effect when you want something from the browser itself while using Roc instead of JavaScript. You call it like any other effect, with typed arguments and a typed answer, so there are no strings to pack and unpack. And its JavaScript is built into your app, so it works on every page the app is put on, with no script for the page to add."),
			],
		),
		h2([], [text("Sharing it with others")]),
		p(
			[],
			[
				text("The folder is a Roc package like any other, so a custom effect that proves useful can be released. Give "),
				c("roc bundle"),
				text(" the "),
				c(".js"),
				text(" files along with the Roc files, as it packs only what it is given. A release names one Joy release as its platform, and works with apps on that release. A package that brings custom effects runs its JavaScript in your pages, so be careful what you depend on from a security, performance, and stability perspective. Roc's great runtime guarantees do not extend to JavaScript."),
			],
		),
	]
}

c : Str -> Html([])
c = |source| code([], [text(source)])
