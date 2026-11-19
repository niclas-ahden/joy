## All your notes. This belongs to the app, not to a page (see `Model` in
## app.roc).
##
## `notes` holds the notes themselves.
## `next_id` holds the id the next note will get. It only ever goes up, so
##           an id is never reused, even after its note has been removed.
Notebook := { notes : List(Note), next_id : U64 }.{
	Note : { id : U64, text : Str }

	start : Notebook
	start = Notebook.{
		notes: [
			{ id: 1, text: "Read the About page" },
			{ id: 2, text: "Search these notes" },
			{ id: 3, text: "Get a quote on the Quote page" },
		],
		next_id: 4,
	}

	add : Notebook, Str -> Try(Notebook, [Blank])
	add = |notebook, typed| {
		text = typed.trim()
		if text.is_empty() {
			Err(Blank)
		} else {
			Ok({ notes: notebook.notes.append({ id: notebook.next_id, text }), next_id: notebook.next_id + 1 })
		}
	}

	remove : Notebook, U64 -> Notebook
	remove = |notebook, note_id| { ..notebook, notes: notebook.notes.keep_if(|note| note.id != note_id) }

	count : Notebook -> U64
	count = |notebook| notebook.notes.len()

	text_of : Notebook, U64 -> Try(Str, [NoSuchNote])
	text_of = |notebook, note_id|
		match notebook.notes.find_first(|note| note.id == note_id) {
			Ok(note) => Ok(note.text)
			Err(_) => Err(NoSuchNote)
		}

	## Find the notes containing `typed`. Ignores upper and lower case, and
	## spaces around it. An empty search finds every note.
	matching : Notebook, Str -> List(Note)
	matching = |notebook, typed| {
		wanted = typed.trim().with_ascii_lowercased()
		notebook.notes.keep_if(|note| note.text.with_ascii_lowercased().contains(wanted))
	}
}
