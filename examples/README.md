# Joy examples

New to Joy? Welcome! Check out [the guide](https://niclas-ahden.github.io/joy/), it gets you going step-by-step and gives you examples to edit right in the browser.

## Templates

The folders in [`templates/`](templates) are the apps `joy init` starts you from. You don't need to copy them from here: run `joy init` in an empty folder, pick one, and it's written into your folder with everything set up. [The guide](https://niclas-ahden.github.io/joy/#install) shows the command.

Have a look at them here to decide which one to pick:

| Template | What you get |
|---|---|
| [`spa-minimal`](templates/spa-minimal) | A single file with a counter. Pick this one if you're new to Joy. |
| [`spa-pages`](templates/spa-pages) | Routing and pages, with one state for the whole app. |
| [`spa-pages-expanded`](templates/spa-pages-expanded) | Like `spa-pages`, with state and messages per page. For bigger apps. |

## Other examples

### TodoMVC

[`spa-todomvc`](spa-todomvc) is [TodoMVC](https://todomvc.com) in Joy: a small but complete app, with browser tests. Read it to see how a real app fits together, or [run it in your browser](https://niclas-ahden.github.io/joy/#example-todomvc).

### One thing at a time

Each of these is a single file that shows one feature. Run opens its page in the guide, where you can edit it and see it run. The voice memo needs your microphone, which the guide's editors cannot use, so that one runs from a clone only:

| Example | What it shows | |
|---|---|---|
| [`hello.roc`](hello.roc) | The smallest Joy app. | [Run](https://niclas-ahden.github.io/joy/#example-hello) |
| [`counter.roc`](counter.roc) | A model, messages and buttons. | [Run](https://niclas-ahden.github.io/joy/#example-counter) |
| [`counters.roc`](counters.roc) | Messages that carry values. | [Run](https://niclas-ahden.github.io/joy/#example-counters) |
| [`events_input.roc`](events_input.roc) | Text inputs and what the user typed. | [Run](https://niclas-ahden.github.io/joy/#example-inputs) |
| [`keyboard.roc`](keyboard.roc) | Key presses. | [Run](https://niclas-ahden.github.io/joy/#example-keyboard) |
| [`pointer.roc`](pointer.roc) | Mouse, touch and pen. | [Run](https://niclas-ahden.github.io/joy/#example-pointer) |
| [`stop_propagation.roc`](stop_propagation.roc) | Stopping a click from reaching the elements around it. | [Run](https://niclas-ahden.github.io/joy/#example-stop-propagation) |
| [`keyed_list.roc`](keyed_list.roc) | Lists whose items move, with `Html.keyed`. | [Run](https://niclas-ahden.github.io/joy/#example-keyed-list) |
| [`modal.roc`](modal.roc) | Dialogs with the browser's own `<dialog>`. | [Run](https://niclas-ahden.github.io/joy/#example-modal) |
| [`flags.roc`](flags.roc) | Passing data to your app when it starts. | [Guide](https://niclas-ahden.github.io/joy/#flags) |
| [`http.roc`](http.roc) | HTTP requests. | [Run](https://niclas-ahden.github.io/joy/#example-http) |
| [`time.roc`](time.roc) | A message every second. | [Run](https://niclas-ahden.github.io/joy/#example-time) |
| [`debounce.roc`](debounce.roc) | Search as you type, waiting until the typing pauses. | [Run](https://niclas-ahden.github.io/joy/#example-debounce) |
| [`voice_memo.roc`](voice_memo.roc) | Recording from the microphone and playing it back. |  |
| [`navigation.roc`](navigation.roc) | Pages with a URL each, and links between them. | [Run](https://niclas-ahden.github.io/joy/#example-navigation) |
| [`ports.roc`](ports.roc) | Talking to your own JavaScript. | [Guide](https://niclas-ahden.github.io/joy/#ports) |
| [`logging.roc`](logging.roc) | Writing to the browser's console. | [Run](https://niclas-ahden.github.io/joy/#example-logging) |

