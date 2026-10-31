# The server of tests/e2e/hot_project, which renders the bundle's first view by
# hand, answers a GET and writes a line for each POST.
app [main!] {
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/growthagent/joy-cli-platform/releases/download/0.1.0-rc1/71QJT9cSt2W6XM4ovm4w6A2PAnq9uUpzn7jxT8PiTGqX.tar.zst",
	shared: "../shared/main.roc",
}

import pf.Env
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sleep
import pf.Stdout
import http.Request
import http.Response
import shared.Greeting

version = "version one"

page : Str
page =
	Str.join_with(
		[
			"<!doctype html><html><head><title>t</title></head><body>",
			"<div id=\"app\" data-joy-bundle=\"app\" data-joy-flags=\"${version}\">",
			"<div id=\"page\"><h1 id=\"title\">${version}</h1><span id=\"shared\">${Greeting.text}</span><span id=\"view\"></span><span id=\"label\"></span>",
			"<button id=\"inc\">+</button><span id=\"count\">0</span><input id=\"name\" value=\"\">",
			"<button id=\"open\">open</button><dialog id=\"dlg\">hello</dialog><button id=\"load\">load</button>",
			"<span id=\"data\"></span><button id=\"save\">save</button><span id=\"saved\"></span></div></div>",
			"<script type=\"module\" src=\"/joy.js\"></script></body></html>",
		],
		"",
	)

answer = |type, text| Ok(Server.respond(Response.from_status(200).with_headers([{ name: "Content-Type", value: type }]).with_body(Str.to_utf8(text))))

respond! = |request| {
	uri = Request.uri(request)
	if uri == "/api/data" {
		answer("text/plain", "data for ${version}")
	} else if uri == "/api/save" {
		log = Path.utf8(".joy/save.log")
		before = log.read_utf8!() ?? ""
		_ = log.write_utf8!("${before}saved\n")
		answer("text/plain", "saved by ${version}")
	} else {
		answer("text/html", page)
	}
}

main! : List(OsStr) => Try({}, _)
main! = |_args| {
	port = U16.from_str(Env.var_str!(OsStr.from_str("PORT")) ?? "0") ?? 0
	server = Server.start!({ port: port }, respond!)?
	Stdout.line!("app listening on ${U16.to_str(server.port())}")?
	_ = Sleep.millis!(1_000_000_000)
	Server.stop!(server)
	Ok({})
}
