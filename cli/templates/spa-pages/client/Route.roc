import url.Uri

## All the URLs of the app, as one type.
##
## `parse` turns a URL into a `Route`.
## `to_path` turns a `Route` back into a URL. Use it for your links, so that
##           URLs are only ever written in this file.
Route := [].{
	Route : [Home, Quote, About]

	parse : Str -> Try(Route.Route, [NotFound])
	parse = |url|
		match Uri.parse(url).path().split_on("/").drop_if(|segment| segment.is_empty()) {
			[] => Ok(Home)
			["quote"] => Ok(Quote)
			["about"] => Ok(About)
			_ => Err(NotFound)
		}

	to_path : Route.Route -> Str
	to_path = |route|
		match route {
			Home => "/"
			Quote => "/quote"
			About => "/about"
		}

	label : Route.Route -> Str
	label = |route|
		match route {
			Home => "Home"
			Quote => "Quote"
			About => "About"
		}

	menu : List(Route.Route)
	menu = [Home, Quote, About]
}
