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
