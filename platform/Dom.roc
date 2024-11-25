module [
    getInnerHtml!,
]

import Effect

getInnerHtml! : Str => Result Str [NotFoundErr]_
getInnerHtml! = \node ->
    Effect.getInnerHtml! node
    |> Result.mapErr \{} -> NotFoundErr
