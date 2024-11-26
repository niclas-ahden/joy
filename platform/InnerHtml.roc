module [
    HtmlForApp,
    EventForApp,
    translateHtmlForApp,
    prepareForHost,
]

import Action exposing [Action]

EventForApp state : {
    name: Str,
    handler: state -> Action state,
}

HtmlForApp state : [
    Text Str,
    Element {
        tag : Str,
        attrs : List (Str, Str),
        events : List (EventForApp state),
    } (List (HtmlForApp state)),
]

translateEventForApp : EventForApp child, (parent -> child), (parent, child -> parent) -> EventForApp parent
translateEventForApp = \{name, handler}, parentToChild, childToParent ->
    {
        name,
        handler: \prevParent ->
            Action.map
                (handler (parentToChild prevParent))
                \child -> childToParent prevParent child
    }

translateHtmlForApp : HtmlForApp child, (parent -> child), (parent, child -> parent) -> HtmlForApp parent
translateHtmlForApp = \elem, parentToChild, childToParent ->
    when elem is
        Text str ->
            Text str

        Element {tag, attrs, events} children ->
            Element
                {
                    tag,
                    attrs,
                    events: List.map events \e -> translateEventForApp e parentToChild childToParent,
                }
                (List.map children \c -> translateHtmlForApp c parentToChild childToParent)

HtmlForHost : [
    Text Str,
    Element {
        tag : Str,
        attrs : List { key: Str, val : Str },
        events : List U64,
    } (List (HtmlForHost)),
]

prepareForHost : HtmlForApp state, U64, List (EventForApp state) -> (HtmlForHost, List (EventForApp state))
prepareForHost = \elem, nextId, acc ->
    when elem is
        Text str ->
            (Text str, acc)

        Element {tag, attrs, events} children ->

            # First handle the events at this level
            (newNextId, eventIds) = replaceEventsWithId events (nextId, [])
            newAcc = List.concat acc events

            # Then recursively handle children
            (processedChildren, finalAcc) =
                List.walk
                    children
                    ([], newAcc)
                    \(childrenAcc, accEvents), child ->
                        (processedChild, newAccEvents) = prepareForHost child newNextId accEvents
                        (List.append childrenAcc processedChild, newAccEvents)

            # Convert attrs format
            formattedAttrs = List.map attrs \(key, val) -> { key, val }

            element = Element {
                tag,
                attrs: formattedAttrs,
                events: eventIds,
            } processedChildren

            (element, finalAcc)

replaceEventsWithId : List (EventForApp state), (U64, List U64) -> (U64, List U64)
replaceEventsWithId = \events, (nextId, acc) ->
    when events is
        [] -> (nextId, acc)
        [_, .. as rest] -> replaceEventsWithId rest (nextId + 1, List.append acc nextId)

expect
    events = [ {name: "click", handler: \_ -> Action.none } ]
    actual = replaceEventsWithId events (0, [])
    actual == (1, [0])

expect
    events = [
        {name: "first", handler: \_ -> Action.none },
        {name: "second", handler: \_ -> Action.none },
    ]
    actual = replaceEventsWithId events (0, [])
    actual == (2, [0, 1])

expect
    # Test simple text node
    input = Text "hello"
    (result, events) = prepareForHost input 0 []
    result == Text "hello" && List.isEmpty events

expect
    # Test element with no children and one event
    input = Element {
        tag: "button",
        attrs: [("class", "primary")],
        events: [{name: "click", handler: \_ -> Action.none}]
    } []

    (result, events) = prepareForHost input 0 []

    result == Element {
        tag: "button",
        attrs: [{key: "class", val: "primary"}],
        events: [0]
    } []
    && List.len events == 1

expect
    # Test nested elements with multiple events
    input = Element {
        tag: "div",
        attrs: [("class", "container")],
        events: [{name: "click", handler: \_ -> Action.none}]
    } [
        Element {
            tag: "button",
            attrs: [("class", "btn")],
            events: [{name: "click", handler: \_ -> Action.none}]
        } [],
        Text "Click me"
    ]

    (result, events) = prepareForHost input 0 []

    result == Element {
        tag: "div",
        attrs: [{key: "class", val: "container"}],
        events: [0]
    } [
        Element {
            tag: "button",
            attrs: [{key: "class", val: "btn"}],
            events: [1]
        } [],
        Text "Click me"
    ]
    && List.len events == 2

expect
    # Test element with multiple attributes and no events
    input = Element {
        tag: "input",
        attrs: [
            ("type", "text"),
            ("placeholder", "Enter name"),
            ("class", "input-field")
        ],
        events: []
    } []

    (result, events) = prepareForHost input 0 []

    result == Element {
        tag: "input",
        attrs: [
            {key: "type", val: "text"},
            {key: "placeholder", val: "Enter name"},
            {key: "class", val: "input-field"}
        ],
        events: []
    } []
    && List.isEmpty events
