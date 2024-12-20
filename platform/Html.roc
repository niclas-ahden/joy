module [
    Html,

    # Elements
    a,
    abbr,
    address,
    area,
    article,
    aside,
    audio,
    b,
    base,
    bdi,
    bdo,
    blockquote,
    body,
    br,
    button,
    canvas,
    caption,
    citeElem,
    codeElem,
    col,
    colgroup,
    dataElem,
    datalist,
    dd,
    del,
    details,
    dfn,
    dialog,
    div,
    dl,
    dt,
    em,
    embed,
    fieldset,
    figcaption,
    figure,
    footer,
    formElem,
    h1,
    h2,
    h3,
    h4,
    h5,
    h6,
    head,
    header,
    hr,
    html,
    i,
    iframe,
    img,
    input,
    ins,
    kbd,
    labelElem,
    legend,
    li,
    link,
    main,
    map,
    mark,
    math,
    menu,
    meta,
    meter,
    nav,
    noscript,
    object,
    ol,
    optgroup,
    option,
    output,
    p,
    picture,
    portal,
    pre,
    progress,
    q,
    rp,
    rt,
    ruby,
    s,
    samp,
    script,
    section,
    select,
    slotElem,
    small,
    source,
    spanElem,
    strong,
    styleElem,
    sub,
    summaryElem,
    sup,
    svg,
    table,
    tbody,
    td,
    template,
    text,
    textarea,
    tfoot,
    th,
    thead,
    time,
    titleElem,
    tr,
    track,
    u,
    ul,
    use,
    var,
    video,
    wbr,

    # Attributes
    accept,
    acceptCharset,
    accesskey,
    action,
    align,
    allow,
    alt,
    async,
    autocapitalize,
    autocomplete,
    autofocus,
    autoplay,
    background,
    bgcolor,
    border,
    buffered,
    capture,
    challenge,
    charset,
    checked,
    citeAttr,
    class,
    classList,
    codeAttr,
    codebase,
    color,
    cols,
    colspan,
    content,
    contenteditable,
    contextmenu,
    controls,
    coords,
    crossorigin,
    csp,
    dataAttr,
    datetime,
    decoding,
    default,
    defer,
    dir,
    dirname,
    disabled,
    download,
    draggable,
    enctype,
    enterkeyhint,
    for,
    formAttr,
    formaction,
    formenctype,
    formmethod,
    formnovalidate,
    formtarget,
    headers,
    height,
    hidden,
    high,
    href,
    hreflang,
    httpEquiv,
    icon,
    id,
    importance,
    inputmode,
    integrity,
    intrinsicsize,
    ismap,
    itemprop,
    keytype,
    kind,
    labelAttr,
    lang,
    language,
    list,
    loading,
    loop,
    low,
    manifest,
    max,
    maxlength,
    media,
    method,
    min,
    minlength,
    multiple,
    muted,
    name,
    novalidate,
    open,
    optimum,
    pattern,
    ping,
    placeholder,
    poster,
    preload,
    radiogroup,
    readonly,
    referrerpolicy,
    rel,
    required,
    reversed,
    role,
    rows,
    rowspan,
    sandbox,
    scope,
    scoped,
    selected,
    shape,
    size,
    sizes,
    slotAttr,
    spanAttr,
    spellcheck,
    src,
    srcdoc,
    srclang,
    srcset,
    start,
    step,
    styleAttr,
    summaryAttr,
    tabindex,
    target,
    titleAttr,
    translate,
    type,
    usemap,
    value,
    width,
    wrap,
]

Html state : [
    None,
    Text Str,
    Element
        {
            tag : Str,
            attrs : List { key : Str, value : Str },
            events : List { name : Str, handler : Str },
        }
        (List (Html state)),
]

# translate : Html child, (parent -> child), (parent, child -> parent) -> Html parent
# translate = \elem, parentToChild, childToParent ->
#     when elem is
#         None ->
#             None
#
#         Text str ->
#             Text str
#
#         Element { tag, attrs, events } children ->
#             Element
#                 { tag, attrs, events }
#                 (List.map children \c -> translate c parentToChild childToParent)

text : Str -> Html state
text = \str -> Text str

element : Str -> (List { key : Str, value : Str }, List (Html state) -> Html state)
element = \tag ->
    \attrs, children -> Element { tag, attrs, events: [] } children

elementWithEvents : Str -> (List { key : Str, value : Str }, List { name : Str, handler : Str }, List (Html state) -> Html state)
elementWithEvents = \tag ->
    \attrs, events, children -> Element { tag, attrs, events } children

# Elements

# TODO: How do we want to handle events long-term?
input = elementWithEvents "input"
button = elementWithEvents "button"
textarea = elementWithEvents "textarea"
select = elementWithEvents "select"

# TODO: These elements conflict with the attributes of the same names. Do we:
#
# A) Use separate modules for elements and attributes

#    This creates visual clutter even when abbreviated to one-letter module names:
#
#        Html.span [ Attribute.class ...
#        H.span [ A.class ...
#
#    Many frameworks opt for this, but can we find another way?
#
# B) Alternative A but only for conflicting names. This minimizes clutter, is explicit, but isn't
#    very discoverable.
#
# C) Alter the name of conflicting functions. E.g. `styleElem` and `styleAttr`. Low clutter, is
#    explicit, is discoverable via auto-complete.
#
# D) ???
#
# Going with option C for now. Conflicting cases so far:
styleElem = element "style"
titleElem = element "title"
citeElem = element "cite"
codeElem = element "code"
dataElem = element "data"
spanElem = element "span"
formElem = element "form"
labelElem = element "label"
summaryElem = element "summary"
slotElem = element "slot"

html = element "html"
base = element "base"
head = element "head"
link = element "link"
meta = element "meta"
body = element "body"
address = element "address"
article = element "article"
aside = element "aside"
footer = element "footer"
header = element "header"
h1 = element "h1"
h2 = element "h2"
h3 = element "h3"
h4 = element "h4"
h5 = element "h5"
h6 = element "h6"
main = element "main"
nav = element "nav"
section = element "section"
blockquote = element "blockquote"
dd = element "dd"
div = element "div"
dl = element "dl"
dt = element "dt"
figcaption = element "figcaption"
figure = element "figure"
hr = element "hr"
li = element "li"
menu = element "menu"
ol = element "ol"
p = element "p"
pre = element "pre"
ul = element "ul"
a = element "a"
abbr = element "abbr"
b = element "b"
bdi = element "bdi"
bdo = element "bdo"
br = element "br"
dfn = element "dfn"
em = element "em"
i = element "i"
kbd = element "kbd"
mark = element "mark"
q = element "q"
rp = element "rp"
rt = element "rt"
ruby = element "ruby"
s = element "s"
samp = element "samp"
small = element "small"
strong = element "strong"
sub = element "sub"
sup = element "sup"
time = element "time"
u = element "u"
var = element "var"
wbr = element "wbr"
area = element "area"
audio = element "audio"
img = element "img"
map = element "map"
track = element "track"
video = element "video"
embed = element "embed"
iframe = element "iframe"
object = element "object"
picture = element "picture"
portal = element "portal"
source = element "source"
svg = element "svg"
math = element "math"
canvas = element "canvas"
noscript = element "noscript"
script = element "script"
del = element "del"
ins = element "ins"
caption = element "caption"
col = element "col"
colgroup = element "colgroup"
table = element "table"
tbody = element "tbody"
td = element "td"
tfoot = element "tfoot"
th = element "th"
thead = element "thead"
tr = element "tr"
datalist = element "datalist"
fieldset = element "fieldset"
legend = element "legend"
meter = element "meter"
optgroup = element "optgroup"
option = element "option"
output = element "output"
progress = element "progress"
details = element "details"
dialog = element "dialog"
template = element "template"
use = element "use"

# Attributes

attribute : Str -> (Str -> { key : Str, value : Str })
attribute = \key -> \v -> { key, value: v }

accept = attribute "accept"
acceptCharset = attribute "acceptCharset"
accesskey = attribute "accesskey"
action = attribute "action"
align = attribute "align"
allow = attribute "allow"
alt = attribute "alt"
async = attribute "async"
autocapitalize = attribute "autocapitalize"
autocomplete = attribute "autocomplete"
autofocus = attribute "autofocus"
autoplay = attribute "autoplay"
background = attribute "background"
bgcolor = attribute "bgcolor"
border = attribute "border"
buffered = attribute "buffered"
capture = attribute "capture"
challenge = attribute "challenge"
charset = attribute "charset"
citeAttr = attribute "cite"
class = attribute "class"
codeAttr = attribute "code"
codebase = attribute "codebase"
color = attribute "color"
cols = attribute "cols"
colspan = attribute "colspan"
content = attribute "content"
contenteditable = attribute "contenteditable"
contextmenu = attribute "contextmenu"
controls = attribute "controls"
coords = attribute "coords"
crossorigin = attribute "crossorigin"
csp = attribute "csp"
dataAttr = attribute "data"
datetime = attribute "datetime"
decoding = attribute "decoding"
default = attribute "default"
defer = attribute "defer"
dir = attribute "dir"
dirname = attribute "dirname"
download = attribute "download"
draggable = attribute "draggable"
enctype = attribute "enctype"
enterkeyhint = attribute "enterkeyhint"
for = attribute "for"
formAttr = attribute "form"
formaction = attribute "formaction"
formenctype = attribute "formenctype"
formmethod = attribute "formmethod"
formnovalidate = attribute "formnovalidate"
formtarget = attribute "formtarget"
headers = attribute "headers"
height = attribute "height"
hidden = attribute "hidden"
high = attribute "high"
href = attribute "href"
hreflang = attribute "hreflang"
httpEquiv = attribute "httpEquiv"
icon = attribute "icon"
id = attribute "id"
importance = attribute "importance"
inputmode = attribute "inputmode"
integrity = attribute "integrity"
intrinsicsize = attribute "intrinsicsize"
ismap = attribute "ismap"
itemprop = attribute "itemprop"
keytype = attribute "keytype"
kind = attribute "kind"
labelAttr = attribute "label"
lang = attribute "lang"
language = attribute "language"
list = attribute "list"
loading = attribute "loading"
loop = attribute "loop"
low = attribute "low"
manifest = attribute "manifest"
max = attribute "max"
maxlength = attribute "maxlength"
media = attribute "media"
method = attribute "method"
min = attribute "min"
minlength = attribute "minlength"
multiple = attribute "multiple"
muted = attribute "muted"
name = attribute "name"
novalidate = attribute "novalidate"
open = attribute "open"
optimum = attribute "optimum"
pattern = attribute "pattern"
ping = attribute "ping"
placeholder = attribute "placeholder"
poster = attribute "poster"
preload = attribute "preload"
radiogroup = attribute "radiogroup"
readonly = attribute "readonly"
referrerpolicy = attribute "referrerpolicy"
rel = attribute "rel"
required = attribute "required"
reversed = attribute "reversed"
role = attribute "role"
rows = attribute "rows"
rowspan = attribute "rowspan"
sandbox = attribute "sandbox"
scope = attribute "scope"
scoped = attribute "scoped"
selected = attribute "selected"
shape = attribute "shape"
size = attribute "size"
sizes = attribute "sizes"
slotAttr = attribute "slot"
spanAttr = attribute "span"
spellcheck = attribute "spellcheck"
src = attribute "src"
srcdoc = attribute "srcdoc"
srclang = attribute "srclang"
srcset = attribute "srcset"
start = attribute "start"
step = attribute "step"
summaryAttr = attribute "summary"
tabindex = attribute "tabindex"
target = attribute "target"
titleAttr = attribute "title"
translate = attribute "translate"
type = attribute "type"
usemap = attribute "usemap"
value = attribute "value"
width = attribute "width"
wrap = attribute "wrap"

classList : List (Str, Bool) -> { key : Str, value : Str }
classList = \classes ->
    val =
        classes
        |> List.keepIf \(_, active) -> active
        |> List.map \(klass, _) -> klass
        |> Str.joinWith " "

    { key: "class", value: val }

styleAttr : List (Str, Str) -> { key : Str, value : Str }
styleAttr = \styles ->
    val =
        List.map styles \(k, v) -> "$(k): $(v)"
        |> Str.joinWith ";"

    { key: "style", value: val }

# Boolean attributes: https://chinedufn.github.io/percy/html-macro/boolean-attributes/index.html

booleanAttribute : Str, Bool -> { key : Str, value : Str }
booleanAttribute = \key, val -> { key, value: if val then "true" else "false" }

## `checked` is a boolean/binary attribute. Given `Bool.true` it'll be present on the element,
## otherwise it'll be absent. It's impossible to set it to a certain value like other attributes
## (e.g. `checked="true"` or `checked="1"`).
##
## This platform uses `percy-dom` to render HTML and `percy-dom` treats `checked` in a non-standard
## way. Usually `checked` is used to determine if the element is checked by default on first
## render, but it will not be affected if a user checks/unchecks the element later. There's a
## different way to access the current state of the element, but it's not this attribute. However,
## `percy-dom` goes against the grain and _does_ use this attribute to set the current state of the
## element. This makes for an ergonomic API:
##
##     input [ type "checkbox", checked isChecked ] [ { name: "onclick", handler: ...
##
## If the `onclick` event toggles the value of `isChecked`, the element will be re-rendered and its
## state will change to reflect its current "checkedness".
##
## Read more:
## https://chinedufn.github.io/percy/html-macro/boolean-attributes/index.html
## https://chinedufn.github.io/percy/html-macro/special-attributes/index.html
checked : Bool -> { key : Str, value : Str }
checked = \bool -> booleanAttribute "checked" bool

## `disabled` is a boolean/binary attribute. Given `Bool.true` it'll be present on the element,
## otherwise it'll be absent. It's impossible to set it to a certain value like other attributes
## (e.g. `disabled="true"` or `disabled="1"`).
disabled : Bool -> { key : Str, value : Str }
disabled = \bool -> booleanAttribute "disabled" bool

# Special attributes: https://chinedufn.github.io/percy/html-macro/special-attributes/index.html
# TODO: Do we need special treatment of `value`?
