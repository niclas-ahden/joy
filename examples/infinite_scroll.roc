app [Model, init!, update!, render] {
    pf: platform "../platform/main.roc",
    # `Attribute.on_visible` needs a joy-html that ships the constructor. Pinned to the
    # local package until that release is published, then re-pin to the release URL.
    html: "https://github.com/niclas-ahden/joy-html/releases/download/0.14.0/IVK93mBqjterEFSYijs67Dkl1rYfu0qGl4PAhSPGET0.tar.br",
}

import html.Html exposing [Html, div, text]
import html.Attribute exposing [id, style]
import pf.Action exposing [Action]

# A minimal infinite-scroll list. `shown` is how many items are currently rendered. Each
# time the sentinel at the bottom of the list scrolls into view we reveal another batch,
# up to `max_items`.
Model : { shown : U64 }

batch_size : U64
batch_size = 20

max_items : U64
max_items = 100

Event : [
    # Fired by the sentinel's `on_visible` attribute whenever it enters the viewport.
    SentinelVisible,
]

init! : Str => Model
init! = |_flags| { shown: batch_size }

update! : Model, Str, List U8 => Action Model
update! = |model, raw, _payload|
    when decode_event(raw) is
        SentinelVisible ->
            if model.shown >= max_items then
                # Nothing left to reveal. Returning `none` skips the re-render, which also
                # means the sentinel is not re-armed (see `rearm_key` below), so loading
                # stops cleanly here.
                Action.none
            else
                { model & shown: Num.min(model.shown + batch_size, max_items) }
                |> Action.update

render : Model -> Html Model
render = |model|
    items =
        List.range({ start: At(1), end: At(model.shown) })
        |> List.map(
            |n|
                div(
                    [style([("padding", "16px"), ("border-bottom", "1px solid #ddd")])],
                    [text("Item ${Num.to_str(n)}")],
                ),
        )

    sentinel =
        # The infinite-scroll sentinel. `on_visible` attaches an `IntersectionObserver`
        # whose lifetime the renderer ties to this node: it is created when the node mounts
        # (including when hydrating server-rendered HTML) and disconnected if the node is
        # ever removed. There is no manual setup, teardown, or `querySelector`.
        #
        # `root_margin: "200px"` makes the event fire 200px before the sentinel actually
        # reaches the viewport, so the next batch is revealed just ahead of the user
        # reaching the bottom.
        #
        # An IntersectionObserver only fires on a crossing into view. After a batch is
        # revealed the sentinel can still be on screen, and with no new crossing it would
        # not fire again, so loading would stall. `rearm_key` changes per batch (here the
        # shown count), which tells the renderer to re-check visibility after each reveal,
        # so loading continues until the sentinel is off-screen or `max_items` is reached.
        # A constant `rearm_key` fires once per crossing.
        div(
            [
                id("sentinel"),
                Attribute.on_visible(
                    {
                        root_margin: "200px",
                        on_visible: encode_event(SentinelVisible),
                        rearm_key: Num.to_str(model.shown),
                    },
                ),
            ],
            [text(if model.shown >= max_items then "No more items" else "Loading more...")],
        )

    div([], List.concat(items, [sentinel]))

encode_event : _ -> Str
encode_event = |event| Inspect.to_str(event)

decode_event : Str -> Event
decode_event = |raw|
    when raw is
        "SentinelVisible" -> SentinelVisible
        _ -> crash("Unsupported event type \"${raw}\"")
