module [
    Action,
    none,
    update,
    map,
]

## The return type of event handlers. Either `None` (no state change) or `Update state`.
Action state : [
    None,
    Update state,
]

## No state change; the view will not re-render.
none : Action _
none = None

## Replace the current state, triggering a re-render.
update : state -> Action state
update = |state| Update(state)

## Transform the state inside an `Update`, or pass through `None`.
map : Action a, (a -> b) -> Action b
map = |action, transform|
    when action is
        None -> None
        Update(state) -> Update(transform(state))

expect map(None, |x| x + 1) == None
expect map(Update(5), |x| x + 1) == Update(6)
expect map(Update("hello"), Str.count_utf8_bytes) == Update(5)
