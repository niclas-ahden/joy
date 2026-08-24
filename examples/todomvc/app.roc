app [Model, Msg, init, update, render, subscriptions] {
	pf: platform "../../platform/main.roc",
	html: "https://github.com/niclas-ahden/joy-html/releases/download/0.16.0/56NBT6VkQ5xm87Wjzcv9mRuNT4RACiAmuAmPbXwc8cuk.tar.zst",
}

import html.Html exposing [Html, a, button, div, footer, h1, header, input, label, li, p, section, span, strong, text, ul]
import html.Attribute exposing [autofocus, checked, class, class_list, for_, id, on, on_check, on_click, on_input, on_key, placeholder, type, value]
import pf.Effect exposing [Effect]

# TodoMVC (https://todomvc.com) as a client-side Joy app. All state lives in
# the model, so a page reload starts you over. The page, styles and browser
# tests live next to this file, so the whole example is this one directory.

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
	UserClickedFilter(Filter),
	UserClickedClearCompleted,
	UserDoubleClickedTodo(U64, Str),
	UserTypedEdit(Str),
	UserCommittedEdit,
	UserCancelledEdit,
]

subscriptions = |_model| []

init : Str -> (Model, List(Effect(Msg)))
init = |_flags|
	({ todos: [], draft: "", filter: All, next_id: 1, editing: NotEditing }, [])

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
					todos: model.todos.map(|t| if t.id == todo_id ({ ..t, done: now }) else t),
				},
				[],
			)

		UserClickedDestroy(todo_id) =>
			({ ..model, todos: model.todos.keep_if(|t| t.id != todo_id) }, [])

		UserToggledAll(now) =>
			({ ..model, todos: model.todos.map(|t| ({ ..t, done: now })) }, [])

		UserClickedFilter(filter) => ({ ..model, filter: filter }, [])

		UserClickedClearCompleted =>
			({ ..model, todos: model.todos.keep_if(|t| !t.done) }, [])

		UserDoubleClickedTodo(todo_id, title) =>
			({ ..model, editing: Editing(todo_id, title) }, [])

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
						model.todos.map(|t| if t.id == todo_id ({ ..t, title: title }) else t)
					}
					({ ..model, todos: todos, editing: NotEditing }, [])
				}
				NotEditing => (model, [])
			}

		UserCancelledEdit => ({ ..model, editing: NotEditing }, [])
	}

render : Model -> Html(Msg)
render = |model| {
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
			ul([class("todo-list")], visible.map(|t| view_todo(t, model.editing))),
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
	shown_value = if is_editing edit_text else todo.title

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
					button([class("destroy"), on_click(UserClickedDestroy(todo.id))], []),
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
					|e| if e.key == "Enter" UserCommittedEdit else UserCancelledEdit,
				),
			]),
		],
	)
}

view_footer : Model -> Html(Msg)
view_footer = |model| {
	active_count = model.todos.count_if(|t| !t.done)
	completed_count = model.todos.len() - active_count
	items = if active_count == 1 "item" else "items"

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
					view_filter("All", All, model.filter),
					view_filter("Active", Active, model.filter),
					view_filter("Completed", Completed, model.filter),
				],
			),
		].concat(clear),
	)
}

view_filter : Str, Filter, Filter -> Html(Msg)
view_filter = |label_text, filter, current|
	li(
		[],
		[
			a(
				[
					class_list([("selected", filter == current)]),
					on_click(UserClickedFilter(filter)),
				],
				[text(label_text)],
			),
		],
	)
