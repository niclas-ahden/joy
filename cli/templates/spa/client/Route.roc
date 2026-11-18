## Every URL the app has, as one type. The links are built from it with
## `to_path`, and `parse` turns a URL back into it, so each URL is spelled in
## one place.
Route := [].{
	Route : [Home, About]

	## The route a URL names. A query or a fragment after the path does not
	## count.
	parse : Str -> Try(Route.Route, [NotFound])
	parse = |url| {
		without_fragment =
			match url.split_first("#") {
				Ok({ before, .. }) => before
				Err(_) => url
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

# The compiler cannot see a route that `parse` forgets, so each route goes
# through `to_path` and back here.
expect Route.parse(Route.to_path(Home)) == Ok(Home)
expect Route.parse(Route.to_path(About)) == Ok(About)
expect Route.parse("/about?from=menu#top") == Ok(About)
expect Route.parse("/nowhere") == Err(NotFound)
