import html.Html exposing [h1, p, text]
import html.Attribute exposing [class]
import /Doc
import "../../examples/hello.roc" as hello : Str
import "../../examples/counter.roc" as counter : Str
import "../../examples/counters.roc" as counters : Str
import "../../examples/events_input.roc" as events_input : Str
import "../../examples/keyboard.roc" as keyboard : Str
import "../../examples/pointer.roc" as pointer : Str
import "../../examples/stop_propagation.roc" as stop_propagation : Str
import "../../examples/keyed_list.roc" as keyed_list : Str
import "../../examples/modal.roc" as modal : Str
import "../../examples/http.roc" as http : Str
import "../../examples/time.roc" as time : Str
import "../../examples/debounce.roc" as debounce : Str
import "../../examples/logging.roc" as logging : Str
import "../../examples/navigation.roc" as navigation : Str
import "../../examples/spa-todomvc/client/app.roc" as todomvc : Str
import "../pages/todomvc.html" as todomvc_page : Str

## The topics of the part "Examples": one page for each example, with the
## example itself to edit and run. The code is the file in examples/, so a
## page never falls behind it.
Examples := [].{
	Example : [Hello, Counter, Counters, Inputs, Keyboard, Pointer, Http, Time, Debounce, KeyedList, Modal, Navigation, Logging, StopPropagation, TodoMvc]

	## Every example in reading order.
	all : List(Example)
	all = [Hello, Counter, Counters, Inputs, Keyboard, Pointer, Http, Time, Debounce, KeyedList, Modal, Navigation, Logging, StopPropagation, TodoMvc]

	## What the index shows of an example, and finds it by: its #anchor, its
	## title and the words a search matches.
	info : Example -> { id : Str, title : Str, keywords : Str }
	info = |example|
		match example {
			Hello => { id: "example-hello", title: "Hello", keywords: "example hello world smallest app text" }
			Counter => { id: "example-counter", title: "Counter", keywords: "example counter model msg update buttons click" }
			Counters => { id: "example-counters", title: "Counters", keywords: "example counters messages payload values several" }
			Inputs => { id: "example-inputs", title: "Inputs", keywords: "example input text field checkbox form submit on_input on_check typed" }
			Keyboard => { id: "example-keyboard", title: "Keyboard", keywords: "example keyboard keys key press keydown escape on_key" }
			Pointer => { id: "example-pointer", title: "Mouse / Touch", keywords: "example pointer mouse touch pen drag coordinates" }
			StopPropagation => { id: "example-stop-propagation", title: "Stop propagation", keywords: "example click bubble bubbling stop propagation event" }
			KeyedList => { id: "example-keyed-list", title: "Keyed list", keywords: "example keyed list keys reorder move items Html.keyed" }
			Modal => { id: "example-modal", title: "Modal", keywords: "example modal dialog show close confirm" }
			Http => { id: "example-http", title: "HTTP", keywords: "example http request get fetch api response json" }
			Time => { id: "example-time", title: "Time", keywords: "example time every second tick interval subscription" }
			Debounce => { id: "example-debounce", title: "Debounce", keywords: "example debounce search type pause timer cancel" }
			Logging => { id: "example-logging", title: "Logging", keywords: "example logging console log dbg debug" }
			Navigation => { id: "example-navigation", title: "Navigation", keywords: "example navigation url link pages push_url replace_url navigate on_url_change on_link_click back forward history routing" }
			TodoMvc => { id: "example-todomvc", title: "TodoMVC", keywords: "example todomvc todo list complete app filters edit" }
		}

	body : Example -> Doc.Body
	body = |example| {
		lead = intro(example)
		[
			p([class("eyebrow")], [text("Examples")]),
			h1([], [text(info(example).title)]),
		]
			.concat(if (lead == "") [] else [p([class("lead")], [text(lead)])])
			.append(editor(example))
	}
}

## A few words above an example that needs them.
intro : Examples.Example -> Str
intro = |example|
	match example {
		Hello => "The smallest Joy app: a model, no messages and a view."
		Counter => "A number, two messages and two buttons."
		Counters => "Three counters in one app. It shows that a message can carry a payload: here, which counter it is for."
		Inputs => "Text input, a checkbox and a form submit, with on_input, on_check and on_submit."
		Keyboard => "Key presses, on the whole page and in one field."
		Pointer => "Mouse, touch and pen as one kind of event. Press and drag on the pad."
		StopPropagation => "A click travels up through the elements around the one you clicked, unless a handler stops it."
		KeyedList => "A list whose items move. With keys, Joy moves the elements instead of rewriting each one."
		Modal => "A dialog with the browser's own dialog element."
		Http => "An HTTP request to a public API, and its response."
		Time => "A message every second."
		Debounce => "Search as you type, once the typing pauses."
		Logging => "Writing to the browser's console. Open the console to see it."
		Navigation => "Three pages with a URL each. Links change the URL without loading a page, and Back and Forward work. The editor shows the app's address above it once you follow a link."
		TodoMvc => "A small but complete app. Its page brings a stylesheet, and hands the app its address so the filters work as links. Have a look at index.html."
	}

## The example to edit and run. TodoMVC brings its page.
editor : Examples.Example -> Html([])
editor = |example|
	match example {
		Hello => Doc.example("hello.roc", shown(hello))
		Counter => Doc.example("counter.roc", shown(counter))
		Counters => Doc.example("counters.roc", shown(counters))
		Inputs => Doc.example("events_input.roc", shown(events_input))
		Keyboard => Doc.example("keyboard.roc", shown(keyboard))
		Pointer => Doc.example("pointer.roc", shown(pointer))
		StopPropagation => Doc.example("stop_propagation.roc", shown(stop_propagation))
		KeyedList => Doc.example("keyed_list.roc", shown(keyed_list))
		Modal => Doc.example("modal.roc", shown(modal))
		Http => Doc.example("http.roc", shown(http))
		Time => Doc.example("time.roc", shown(time))
		Debounce => Doc.example("debounce.roc", shown(debounce))
		Logging => Doc.example("logging.roc", shown(logging))
		Navigation => Doc.example("navigation.roc", shown(navigation))
		TodoMvc => Doc.with_page("app.roc", shown(todomvc), todomvc_page)
	}

## An example as the guide shows it: on a release of Joy, as a project of
## your own would be, in place of the path to the platform beside it.
shown : Str -> Str
shown = |source|
	source
		.replace_first("pf: platform \"../platform/main.roc\"", Doc.platform_line)
		.replace_first("pf: platform \"../../../platform/main.roc\"", Doc.platform_line)
