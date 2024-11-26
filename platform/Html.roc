module [Html, translateHtml]

import Action exposing [Action]

Event state : {
    name: Str,
    handler: state -> Action state,
}

Html state : [
    Text Str,
    Element {
        tag : Str,
        attrs : List (Str, Str),
        events : List (Event state),
    } (List (Html state)),
]

translateEvent : Event child, (parent -> child), (parent, child -> parent) -> Event parent
translateEvent = \{name, handler}, parentToChild, childToParent ->
    {
        name,
        handler: \prevParent ->
            Action.map
                (handler (parentToChild prevParent))
                \child -> childToParent prevParent child
    }

translateHtml : Html child, (parent -> child), (parent, child -> parent) -> Html parent
translateHtml = \elem, parentToChild, childToParent ->
    when elem is
        Text text -> Text text
        Element {tag, attrs, events} children ->

            Element
                {
                    tag,
                    attrs,
                    events: List.map events \e -> translateEvent e parentToChild childToParent,
                }
                (List.map children \c -> translateHtml c parentToChild childToParent)
