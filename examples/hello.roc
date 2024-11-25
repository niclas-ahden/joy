app [Model, init] { web: platform "../platform/main.roc" }

Model : I64

init : {} -> Model
init = \{} -> 42
