## Every URL the app has, as one type. The links are built from it with
## `to_path`, and `parse` turns a URL back into it, so each URL is spelled in
## one place.
Route := [].{
	Route : [Home, About]

	## The route a path names. A query or a fragment after it does not count.
	parse : Str -> Try(Route.Route, [NotFound])
	parse = |path| {
		without_fragment =
			match path.split_first("#") {
				Ok({ before, .. }) => before
				Err(_) => path
			}
		without_query =
			match without_fragment.split_first("?") {
				Ok({ before, .. }) => before
				Err(_) => without_fragment
			}
		match without_query.split_on("/").drop_if(|segment| segment.is_empty()) {
			[] => Ok(Home)
			["about"] => Ok(About)
			_ => Err(NotFound)
		}
	}

	to_path : Route.Route -> Str
	to_path = |route|
		match route {
			Home => "/"
			About => "/about"
		}
}

expect Route.parse(Route.to_path(Home)) == Ok(Home)
expect Route.parse(Route.to_path(About)) == Ok(About)
expect Route.parse("/about?from=menu#top") == Ok(About)
expect Route.parse("/nowhere") == Err(NotFound)
