import url.Uri

## All the URLs of the app, as one type.
##
## `parse` turns a URL into a `Route`.
## `to_path` turns a `Route` back into a URL. Use it for your links, so that
##           URLs are only ever written in this file.
Route := [].{
	Route : [
		Notes,

		## A single note by its id, e.g. `/notes/3`.
		Note(U64),
		Quote,
		About,
	]

	parse : Str -> Try(Route.Route, [NotFound])
	parse = |url|
		match Uri.parse(url).path().split_on("/").drop_if(|segment| segment.is_empty()) {
			[] => Ok(Notes)
			["notes", id] => U64.from_str(id).map_ok(|n| Note(n)).map_err(|_| NotFound)
			["quote"] => Ok(Quote)
			["about"] => Ok(About)
			_ => Err(NotFound)
		}

	to_path : Route.Route -> Str
	to_path = |route|
		match route {
			Notes => "/"
			Note(id) => "/notes/${id.to_str()}"
			Quote => "/quote"
			About => "/about"
		}

	label : Route.Route -> Str
	label = |route|
		match route {
			Notes => "Notes"
			Note(id) => "Note ${id.to_str()}"
			Quote => "Quote"
			About => "About"
		}

	menu : List(Route.Route)
	menu = [Notes, Quote, About]
}
