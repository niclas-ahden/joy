app [Model, Msg, init, subscriptions, update, view] {
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.18.0/6XAQypURmG12GNMHHZmjcXVGtctYy52mmPZoaUMWejRK.tar.zst",
	pf: platform "../../../platform/main.roc",
}

import html.Html exposing [a, button, div, footer, h1, header, input, label, li, p, section, span, strong, text, ul]
import html.Attribute exposing [aria, autofocus, checked, class, class_list, for_, href, id, on, on_check, on_click, on_input, on_key, placeholder, type, value]
import pf.DOM
import pf.Effect
import pf.Navigation
import pf.Sub

# TodoMVC (https://todomvc.com) as a client-side Joy app. All state lives in
# the model, so a page reload starts you over. The page is public/index.html,
# the styles are assets/css/style.css and the browser tests are in e2e/.

Todo : { id : U64, title : Str, done : Bool }

Filter : [All, Active, Completed]

# Which todo is being edited, if any, and the text typed so far. The todo's
# own title only changes when the edit commits, so Escape can throw the
# draft away.
Edit : [NotEditing, Editing(U64, Str)]

Model : {
	todos : List(Todo),
	draft : Str,
	filter : Filter,
	next_id : U64,
	editing : Edit,
}

Msg : [
	UserTypedDraft(Str),
	UserSubmittedDraft,
	UserToggledTodo(U64, Bool),
	UserClickedDestroy(U64),
	UserToggledAll(Bool),
	UrlChanged(Str),
	UserClickedClearCompleted,
	UserDoubleClickedTodo(U64, Str),
	UserTypedEdit(Str),
	UserCommittedEdit,
	UserCancelledEdit,
]

# The filters are links to `#/`, `#/active` and `#/completed`, which the
# browser follows on its own. We hear of the new URL here, and of Back and
# Forward too.
subscriptions : Model -> List(Sub(Msg))
subscriptions = |_model| [Navigation.on_url_change(|url| UrlChanged(url))]

# `url` is the URL the page was opened at. public/index.html passes it in as
# the flags, so that a refresh or a shared link opens the right filter.
init : Str -> (Model, List(Effect(Msg)))
init = |url|
	({ todos: [], draft: "", filter: filter_in(url), next_id: 1, editing: NotEditing }, [])

# The filter a URL names. Anything but `#/active` and `#/completed` shows
# every todo.
filter_in : Str -> Filter
filter_in = |url| {
	fragment =
		match url.split_first("#") {
			Ok(split) => split.after
			Err(_) => ""
		}
	match fragment {
		"/active" => Active
		"/completed" => Completed
		_ => All
	}
}

expect filter_in("http://localhost:8000/") == All
expect filter_in("http://localhost:8000/#/") == All
expect filter_in("http://localhost:8000/#/active") == Active
expect filter_in("http://localhost:8000/#/completed") == Completed
expect filter_in("http://localhost:8000/#/nope") == All

update : Model, Msg -> (Model, List(Effect(Msg)))
update = |model, msg|
	match msg {
		UserTypedDraft(draft) => ({ ..model, draft: draft }, [])

		UserSubmittedDraft => {
			title = model.draft.trim()
			if title.is_empty() {
				(model, [])
			} else {
				todo = { id: model.next_id, title: title, done: Bool.False }
				(
					{
						..model,
						todos: model.todos.append(todo),
						draft: "",
						next_id: model.next_id + 1,
					},
					[],
				)
			}
		}

		UserToggledTodo(todo_id, now) =>
			(
				{
					..model,
					todos: model.todos.map(|t| if (t.id == todo_id) ({ ..t, done: now }) else t),
				},
				[],
			)

		UserClickedDestroy(todo_id) =>
			({ ..model, todos: model.todos.keep_if(|t| t.id != todo_id) }, [])

		UserToggledAll(now) =>
			({ ..model, todos: model.todos.map(|t| ({ ..t, done: now })) }, [])

		UrlChanged(url) => ({ ..model, filter: filter_in(url) }, [])

		UserClickedClearCompleted =>
			({ ..model, todos: model.todos.keep_if(|t| !t.done) }, [])

		# The edit field is revealed by this render and focused right after
		# it, so typing can start without a second click.
		UserDoubleClickedTodo(todo_id, title) =>
			({ ..model, editing: Editing(todo_id, title) }, [DOM.focus(".todo-list li.editing .edit")])

		UserTypedEdit(edit_text) =>
			match model.editing {
				Editing(todo_id, _) => ({ ..model, editing: Editing(todo_id, edit_text) }, [])
				NotEditing => (model, [])
			}

		# Fired by both Enter and blur. The blur arrives even when Enter got
		# there first (committing rerenders and drops the input), by which
		# time editing is NotEditing and this is a no-op.
		UserCommittedEdit =>
			match model.editing {
				Editing(todo_id, edit_text) => {
					title = edit_text.trim()
					# Committing an emptied-out todo deletes it, per the TodoMVC spec.
					todos = if title.is_empty() {
						model.todos.keep_if(|t| t.id != todo_id)
					} else {
						model.todos.map(|t| if (t.id == todo_id) ({ ..t, title: title }) else t)
					}
					({ ..model, todos: todos, editing: NotEditing }, [])
				}
				NotEditing => (model, [])
			}

		UserCancelledEdit => ({ ..model, editing: NotEditing }, [])
	}

view : Model -> Html(Msg)
view = |model| {
	visible = match model.filter {
		All => model.todos
		Active => model.todos.keep_if(|t| !t.done)
		Completed => model.todos.keep_if(|t| t.done)
	}

	# The list section and footer only exist while there are todos,
	# again per the TodoMVC spec.
	body = if model.todos.is_empty() {
		[]
	} else {
		[view_main(model, visible), view_footer(model)]
	}

	div(
		[],
		[
			section(
				[class("todoapp")],
				[view_header(model)].concat(body),
			),
			footer(
				[class("info")],
				[p([], [text("Double-click to edit a todo")])],
			),
		],
	)
}

view_header : Model -> Html(Msg)
view_header = |model|
	header(
		[class("header")],
		[
			h1([], [text("todos")]),
			input([
				class("new-todo"),
				placeholder("What needs to be done?"),
				autofocus(Bool.True),
				value(model.draft),
				on_input(|s| UserTypedDraft(s)),
				on_key("keydown", ["Enter"], |_| UserSubmittedDraft),
			]),
		],
	)

view_main : Model, List(Todo) -> Html(Msg)
view_main = |model, visible| {
	all_done = model.todos.count_if(|t| !t.done) == 0
	section(
		[class("main")],
		[
			input([
				id("toggle-all"),
				class("toggle-all"),
				type("checkbox"),
				checked(all_done),
				on_check(|now| UserToggledAll(now)),
			]),
			label([for_("toggle-all")], [text("Mark all as complete")]),
			ul([class("todo-list")], visible.map(|t| Html.keyed(t.id.to_str(), view_todo(t, model.editing)))),
		],
	)
}

view_todo : Todo, Edit -> Html(Msg)
view_todo = |todo, editing| {
	(is_editing, edit_text) = match editing {
		Editing(todo_id, typed) => (todo_id == todo.id, typed)
		NotEditing => (Bool.False, "")
	}

	# Both the view row and the edit input are always rendered, and CSS shows
	# one or the other based on the li's `editing` class. That keeps every render's
	# structure identical, so that we only ever patch attributes and text.
	#
	# While the input is hidden its `value` tracks the todo's title, so each
	# edit starts from the current title. While editing it tracks the typed
	# text, so cancelling can put the title back.
	shown_value = if (is_editing) edit_text else todo.title

	li(
		[
			class_list([("completed", todo.done), ("editing", is_editing)]),
		],
		[
			div(
				[class("view")],
				[
					input([
						class("toggle"),
						type("checkbox"),
						checked(todo.done),
						on_check(|now| UserToggledTodo(todo.id, now)),
					]),
					label(
						[on("dblclick", UserDoubleClickedTodo(todo.id, todo.title))],
						[text(todo.title)],
					),
					button([class("destroy"), aria("label", "Delete ${todo.title}"), on_click(UserClickedDestroy(todo.id))], []),
				],
			),
			input([
				class("edit"),
				value(shown_value),
				on_input(|s| UserTypedEdit(s)),
				# Fires when editing ends however it ends, because hiding
				# the input drops its focus. By then a commit or cancel
				# has already cleared `editing`, so the commit below is a
				# no-op unless focus genuinely moved away mid-edit.
				on("blur", UserCommittedEdit),
				on_key(
					"keydown",
					["Enter", "Escape"],
					|e| if (e.key == "Enter") UserCommittedEdit else UserCancelledEdit,
				),
			]),
		],
	)
}

view_footer : Model -> Html(Msg)
view_footer = |model| {
	active_count = model.todos.count_if(|t| !t.done)
	completed_count = model.todos.len() - active_count
	items = if (active_count == 1) "item" else "items"

	clear = if completed_count == 0 {
		[]
	} else {
		[button([class("clear-completed"), on_click(UserClickedClearCompleted)], [text("Clear completed")])]
	}

	footer(
		[class("footer")],
		[
			span(
				[class("todo-count")],
				[strong([], [text(active_count.to_str())]), text(" ${items} left")],
			),
			ul(
				[class("filters")],
				[
					view_filter("All", "#/", All, model.filter),
					view_filter("Active", "#/active", Active, model.filter),
					view_filter("Completed", "#/completed", Completed, model.filter),
				],
			),
		].concat(clear),
	)
}

# A filter is a real link, so it can be reached with the keyboard, opened in
# a new tab and shared. The one that's on gets `aria-current`, which screen
# readers read out, next to the class the stylesheet highlights it with.
view_filter : Str, Str, Filter, Filter -> Html(Msg)
view_filter = |label_text, url, filter, current| {
	on = if (filter == current) [aria("current", "page")] else []
	li(
		[],
		[
			a(
				[href(url), class_list([("selected", filter == current)])].concat(on),
				[text(label_text)],
			),
		],
	)
}
