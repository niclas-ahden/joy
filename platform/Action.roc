module [
    Action,
    none,
    update,
    map,
]

Action state : [
    None,
    Update state,
]

none : Action _
none = None

update : _ -> Action _
update = Update

map : Action a, (a -> b) -> Action b
map = |action, transform|
    when action is
        None -> None
        Update(state) -> Update(transform(state))
