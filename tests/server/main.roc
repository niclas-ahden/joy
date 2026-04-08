app [Model, init!, respond!] {
    pf: platform "https://github.com/growthagent/basic-webserver/releases/download/0.19.0/iDXsSC5nMLc-S634O1Bjn8swkxJZeYyHHAkVL42phMc.tar.br",
}

import pf.Http exposing [Request, Response]
import pf.File

Model : {}

init! : {} => Result Model []
init! = |_| Ok({})

respond! : Request, Model => Result Response [ServerErr Str]
respond! = |request, _model|
    # Strip query string for routing (basic-webserver includes it in uri)
    path =
        when Str.split_first(request.uri, "?") is
            Ok({ before }) -> before
            Err(_) -> request.uri

    when request.method is
        POST if path == "/echo" -> Ok(echo_response(request))
        PUT if path == "/echo" -> Ok(echo_response(request))
        GET if path == "/echo" -> Ok(echo_response(request))
        GET if path == "/error-500" -> Ok(error_500)
        GET -> serve_static!(path)
        POST if path == "/error-500" -> Ok(error_500)
        _ -> Ok(not_found)

## Echo back the request details as JSON: method, headers, body size, body content (as UTF-8 if valid).
echo_response : Request -> Response
echo_response = |request|
    method_str = when request.method is
        GET -> "GET"
        POST -> "POST"
        PUT -> "PUT"
        DELETE -> "DELETE"
        _ -> "UNKNOWN"

    headers_json =
        request.headers
        |> List.map(|{ name, value }| "\"$(name)\": \"$(value)\"")
        |> Str.join_with(", ")

    body_size = List.len(request.body)
    body_utf8 = request.body |> Str.from_utf8 |> Result.with_default("")

    json_body = "{\"method\": \"$(method_str)\", \"body_size\": $(Num.to_str(body_size)), \"body_utf8\": \"$(body_utf8)\", \"headers\": {$(headers_json)}}"

    {
        status: 200,
        headers: [
            { name: "Content-Type", value: "application/json" },
            { name: "Access-Control-Allow-Origin", value: "*" },
        ],
        body: Str.to_utf8(json_body),
    }

## Serve static files from the test apps directory.
## Maps: / → tests/apps/crypto/www/index.html
##        /crypto → tests/apps/crypto/www/index.html
##        /crypto/pkg/web.js → tests/apps/crypto/www/pkg/web.js
##        /http → tests/apps/http/www/index.html
##        /http/pkg/web.js → tests/apps/http/www/pkg/web.js
serve_static! : Str => Result Response [ServerErr Str]
serve_static! = |uri|
    # Default to crypto app for root
    resolved =
        if uri == "/" then
            "tests/apps/crypto/www/index.html"
        else
            # /crypto/pkg/web.js → tests/apps/crypto/www/pkg/web.js
            # /http/pkg/web.js → tests/apps/http/www/pkg/web.js
            path = if Str.starts_with(uri, "/") then Str.drop_prefix(uri, "/") else uri
            when Str.split_first(path, "/") is
                Ok({ before: app_name, after: rest }) ->
                    if rest == "" then
                        "tests/apps/$(app_name)/www/index.html"
                    else
                        "tests/apps/$(app_name)/www/$(rest)"

                Err(_) ->
                    "tests/apps/$(path)/www/index.html"

    when File.read_bytes!(resolved) is
        Ok(bytes) ->
            content_type = mime_type(resolved)
            Ok({
                status: 200,
                headers: [
                    { name: "Content-Type", value: content_type },
                    { name: "Access-Control-Allow-Origin", value: "*" },
                ],
                body: bytes,
            })

        Err(_) ->
            Ok(not_found)

mime_type : Str -> Str
mime_type = |path|
    if Str.ends_with(path, ".html") then
        "text/html; charset=utf-8"
    else if Str.ends_with(path, ".js") then
        "application/javascript"
    else if Str.ends_with(path, ".wasm") then
        "application/wasm"
    else if Str.ends_with(path, ".json") then
        "application/json"
    else
        "application/octet-stream"

error_500 : Response
error_500 = {
    status: 500,
    headers: [{ name: "Content-Type", value: "application/json" }],
    body: Str.to_utf8("{\"error\": \"Internal Server Error\"}"),
}

not_found : Response
not_found = {
    status: 404,
    headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
    body: Str.to_utf8("404 Not Found"),
}
