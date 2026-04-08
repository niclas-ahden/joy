use roc_std::RocList;
use roc_std::RocStr;
use std::collections::HashMap;
use std::sync::Mutex;
use wasm_bindgen::prelude::*;

// Global storage for debounce timers
static DEBOUNCE_TIMERS: std::sync::LazyLock<Mutex<HashMap<String, i32>>> =
    std::sync::LazyLock::new(|| Mutex::new(HashMap::new()));

// Global storage for File objects selected via <input type="file">.
// Files are stored by numeric ID so Roc can reference them without touching the bytes.
// Uses thread_local because web_sys::File is not Send+Sync (JS objects are single-threaded).
use std::cell::RefCell;
thread_local! {
    static FILE_STORE: RefCell<HashMap<u32, web_sys::File>> = RefCell::new(HashMap::new());
    static NEXT_FILE_ID: RefCell<u32> = RefCell::new(1);
}

mod console;
mod model;
mod pdom;

#[wasm_bindgen]
pub fn run(flags: String) {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));
    // console::log(&format!("Starting app..."));

    let initial_vnode = model::with(|maybe_model| {
        // call into roc to get the initial model
        let boxed_model = roc::roc_init(&flags.as_str().into());

        // save the model for later
        *maybe_model = Some(boxed_model.clone());

        // render the model to html
        let roc_html = roc::roc_render(boxed_model);

        // convert the roc html to percy virtual node
        roc_html_to_percy(&roc_html)
    });

    let app_element = web_sys::window()
        .expect("should have a browser window")
        .document()
        .unwrap()
        .get_element_by_id("app")
        .expect("should have an `#app` element");

    let pdom_instance = if app_element.first_child().is_some() {
        percy_dom::PercyDom::new_hydrate_mount(initial_vnode, app_element)
    } else {
        percy_dom::PercyDom::new_replace_mount(initial_vnode, app_element)
    };

    pdom::set(pdom_instance);

    // Mark that Joy/WASM has fully initialized
    web_sys::window()
        .expect("should have a browser window")
        .document()
        .unwrap()
        .get_element_by_id("app")
        .expect("should have an `#app` element")
        .set_attribute("data-joy-initialized", "")
        .expect("Failed to set data-joy-initialized attribute on #app");
}

#[wasm_bindgen]
pub fn port(event: String) {
    // console::log(&format!("Port received event: {event}"));
    roc_run_event(&event.as_str().into(), &RocList::empty())
}

fn roc_html_to_percy(value: &roc::glue::Html) -> percy_dom::VirtualNode {
    match value.discriminant() {
        roc::glue::DiscriminantHtml::None => percy_dom::VirtualNode::text(""),
        roc::glue::DiscriminantHtml::Text => roc_to_percy_text_node(value),
        roc::glue::DiscriminantHtml::VoidElement => unsafe {
            roc_to_percy_element_node(value, Vec::new())
        },
        roc::glue::DiscriminantHtml::Element => unsafe {
            // convert all the children to percy virtual nodes
            let children: Vec<percy_dom::VirtualNode> = value
                .ptr_read_union()
                .element
                .children
                .into_iter()
                .map(roc_html_to_percy)
                .collect();
            roc_to_percy_element_node(value, children)
        },
    }
}

unsafe fn roc_to_percy_element_node(
    value: &roc::glue::Html,
    children: Vec<percy_dom::VirtualNode>,
) -> percy_dom::VirtualNode {
    let tag = value.ptr_read_union().element.data.tag.as_str().to_owned();
    let roc_attrs = &value.ptr_read_union().element.data.attrs;

    // Separate regular attributes from events
    let mut attrs = std::collections::HashMap::new();
    let mut events = percy_dom::event::Events::new();

    for attr in roc_attrs.into_iter() {
        match attr.discriminant() {
            roc::glue::DiscriminantAttribute::Boolean => {
                let attr_data = attr.borrow_boolean();
                attrs.insert(
                    attr_data.key.to_string(),
                    percy_dom::AttributeValue::Bool(attr_data.value),
                );
            }
            roc::glue::DiscriminantAttribute::String => {
                let attr_data = attr.borrow_string();
                attrs.insert(
                    attr_data.key.to_string(),
                    percy_dom::AttributeValue::String(attr_data.value.to_string()),
                );
            }
            roc::glue::DiscriminantAttribute::Event => {
                let event_data = attr.borrow_event();
                register_event(&mut events, &tag, event_data);
            }
        }
    }

    percy_dom::VirtualNode::Element(percy_dom::VElement {
        tag,
        attrs,
        events,
        children,
        special_attributes: percy_dom::SpecialAttributes::default(),
    })
}

fn register_event(
    events: &mut percy_dom::event::Events,
    tag: &str,
    event_attr: &roc::glue::EventAttr,
) {
    use wasm_bindgen::prelude::*;

    let event_name = event_attr.name.to_string();
    let handler = event_attr.handler.clone();
    let should_stop_propagation = event_attr.stop_propagation;
    let should_prevent_default = event_attr.prevent_default;

    match event_name.as_str() {
        "onclick" => {
            let callback = std::rc::Rc::new(std::cell::RefCell::new(
                move |event: percy_dom::event::MouseEvent| {
                    if should_prevent_default {
                        event.prevent_default();
                    }
                    if should_stop_propagation {
                        event.stop_propagation();
                    }
                    roc_run_event(&handler, &RocList::empty())
                },
            ));
            events.insert_mouse_event(event_name.into(), callback);
        }
        "oninput" | "onchange" | "onkeyup" | "onkeydown" => {
            let tag_owned = tag.to_owned();
            // Use generic Event instead of InputEvent to handle both real keyboard
            // events and synthetic events from Playwright's fill()
            let callback = std::rc::Rc::new(Closure::<dyn FnMut(web_sys::Event)>::new(
                move |e: web_sys::Event| {
                    if should_prevent_default {
                        e.prevent_default();
                    }
                    if should_stop_propagation {
                        e.stop_propagation();
                    }

                    fn current_target<T>(event: &web_sys::Event) -> T
                    where
                        T: wasm_bindgen::JsCast,
                    {
                        event
                            .current_target()
                            .expect("must have a `current_target`")
                            .dyn_into::<T>()
                            .expect("failed to cast `current_target` into element type")
                    }

                    if tag_owned == "input" {
                        let input = current_target::<web_sys::HtmlInputElement>(&e);

                        // File inputs: store the File object and send metadata as JSON
                        if input.type_() == "file" {
                            if let Some(files) = input.files() {
                                if let Some(file) = files.get(0) {
                                    let file_id = NEXT_FILE_ID.with(|id| {
                                        let mut id = id.borrow_mut();
                                        let current = *id;
                                        *id += 1;
                                        current
                                    });

                                    let metadata = format!(
                                        "{{\"file_id\":{},\"name\":\"{}\",\"size\":{},\"type\":\"{}\"}}",
                                        file_id,
                                        file.name().replace('"', "\\\""),
                                        file.size(),
                                        file.type_().replace('"', "\\\""),
                                    );

                                    FILE_STORE.with(|store| {
                                        store.borrow_mut().insert(file_id, file);
                                    });

                                    roc_run_event(
                                        &handler,
                                        &RocList::from_slice(metadata.as_bytes()),
                                    );
                                    return;
                                }
                            }
                            // No file selected (e.g. user cancelled)
                            roc_run_event(&handler, &RocList::empty());
                            return;
                        }

                        // Regular text/number inputs
                        roc_run_event(
                            &handler,
                            &RocList::from_slice(input.value().as_bytes()),
                        );
                    } else {
                        let current_target_value = match tag_owned.as_str() {
                            "textarea" => current_target::<web_sys::HtmlTextAreaElement>(&e).value(),
                            "select" => current_target::<web_sys::HtmlSelectElement>(&e).value(),
                            _ => panic!("Unsupported tag type for input event: {tag_owned}"),
                        };

                        roc_run_event(
                            &handler,
                            &RocList::from_slice(current_target_value.as_bytes()),
                        );
                    }
                },
            ));
            events.__insert_unsupported_signature(event_name.into(), callback);
        }
        "ontouchstart" | "ontouchmove" | "ontouchend" => {
            let callback = std::rc::Rc::new(Closure::<dyn FnMut(web_sys::TouchEvent)>::new(
                move |e: web_sys::TouchEvent| {
                    if should_prevent_default {
                        e.prevent_default();
                    }
                    if should_stop_propagation {
                        e.stop_propagation();
                    }

                    // Get the first touch point's coordinates
                    let payload = if let Some(touch) = e.touches().get(0) {
                        format!("{},{}", touch.client_x(), touch.client_y())
                    } else {
                        // For touchend, use changed_touches
                        if let Some(touch) = e.changed_touches().get(0) {
                            format!("{},{}", touch.client_x(), touch.client_y())
                        } else {
                            "0,0".to_string()
                        }
                    };

                    roc_run_event(&handler, &RocList::from_slice(payload.as_bytes()))
                },
            ));
            events.__insert_unsupported_signature(event_name.into(), callback);
        }
        "onmousedown" | "onmousemove" | "onmouseup" | "onmouseleave" => {
            let callback = std::rc::Rc::new(std::cell::RefCell::new(
                move |event: percy_dom::event::MouseEvent| {
                    if should_prevent_default {
                        event.prevent_default();
                    }
                    if should_stop_propagation {
                        event.stop_propagation();
                    }

                    let payload = format!("{},{}", event.client_x(), event.client_y());
                    roc_run_event(&handler, &RocList::from_slice(payload.as_bytes()))
                },
            ));
            events.insert_mouse_event(event_name.into(), callback);
        }
        _ => panic!("Unsupported event type: {event_name}"),
    }
}

fn roc_run_event(roc_event: &RocStr, event_payload: &RocList<u8>) {
    model::with(|maybe_model| {
        if let Some(boxed_model) = maybe_model {
            let mut action = roc::roc_update(boxed_model.clone(), roc_event, event_payload);

            match action.discriminant() {
                roc::glue::DiscriminantAction::None => {
                    // no action to take
                }
                roc::glue::DiscriminantAction::Update => {
                    // we have a new model
                    let new_model = action.unwrap_model();

                    pdom::with(|pdom| {
                        // pass the new model to roc to render the new html
                        let new_html = roc::roc_render(new_model.clone());

                        // convert the new roc html to percy virtual node
                        let new_vnode = roc_html_to_percy(&new_html);

                        // diff and patch the DOM
                        pdom.update(new_vnode);
                    });

                    // save the new model for later
                    *maybe_model = Some(new_model);
                }
            }
        } else {
            // no model available... what does this mean?
            // might be relevant when we support more events
            panic!("NO MODEL AVAILABLE")
        }
    })
}

fn roc_to_percy_text_node(value: &roc::glue::Html) -> percy_dom::VirtualNode {
    unsafe { percy_dom::VirtualNode::text(value.ptr_read_union().text.str.as_str()) }
}


// Console

#[no_mangle]
pub extern "C" fn roc_fx_console_log(msg: &RocStr) {
    let msg: wasm_bindgen::JsValue = msg.as_str().into();
    web_sys::console::log_1(&msg);
}

// DOM

#[no_mangle]
pub extern "C" fn roc_fx_dom_show_modal(selector: &RocStr) {
    let window = web_sys::window().expect("No global `window` exists");
    let document = window
        .document()
        .expect("Should have a `document` on `window`");

    if let Ok(Some(element)) = document.query_selector(&selector.to_string()) {
        if let Ok(dialog) = element.dyn_into::<web_sys::HtmlDialogElement>() {
            dialog.show_modal().expect("Failed to show modal");
        } else {
            console::log(&format!(
                "Found element, but it's not a dialog: {}",
                selector.to_string()
            ));
        }
    } else {
        console::log(&format!("Element not found: {}", selector.to_string()));
    }
}

#[no_mangle]
pub extern "C" fn roc_fx_dom_close_modal(selector: &RocStr) {
    let window = web_sys::window().expect("No global `window` exists");
    let document = window
        .document()
        .expect("Should have a `document` on `window`");

    if let Ok(Some(element)) = document.query_selector(&selector.to_string()) {
        if let Ok(dialog) = element.dyn_into::<web_sys::HtmlDialogElement>() {
            dialog.close();
        } else {
            console::log(&format!(
                "Found element, but it's not a dialog: {}",
                selector.to_string()
            ));
        }
    } else {
        console::log(&format!("Element not found: {}", selector.to_string()));
    }
}

// HTTP — all requests use the browser fetch API directly (no reqwest dependency).

#[no_mangle]
pub extern "C" fn roc_fx_http_get(url: &RocStr, raw_event: &RocStr) {
    let url_ = resolve_url(url);
    let raw_event_ = raw_event.clone();

    wasm_bindgen_futures::spawn_local(async move {
        let result = fetch("GET", &url_, FetchBody::None, &[]).await;
        roc_run_event(&raw_event_, &RocList::from_slice(result.as_bytes()));
    });
}

#[no_mangle]
pub extern "C" fn roc_fx_http_post(url: &RocStr, body: &RocList<u8>, raw_event: &RocStr) {
    let url_ = resolve_url(url);
    let body_ = body.as_slice().to_vec();
    let raw_event_ = raw_event.clone();

    wasm_bindgen_futures::spawn_local(async move {
        let result = fetch("POST", &url_, FetchBody::Bytes(body_), &[]).await;
        roc_run_event(&raw_event_, &RocList::from_slice(result.as_bytes()));
    });
}

#[no_mangle]
pub extern "C" fn roc_fx_http_put(url: &RocStr, body: &RocList<u8>, raw_event: &RocStr) {
    let url_ = resolve_url(url);
    let body_ = body.as_slice().to_vec();
    let raw_event_ = raw_event.clone();

    wasm_bindgen_futures::spawn_local(async move {
        let result = fetch("PUT", &url_, FetchBody::Bytes(body_), &[]).await;
        roc_run_event(&raw_event_, &RocList::from_slice(result.as_bytes()));
    });
}

#[no_mangle]
pub extern "C" fn roc_fx_http_send_file(
    method: &RocStr,
    url: &RocStr,
    file_id: u32,
    start: u64,
    len: u64,
    headers: &RocList<(RocStr, RocStr)>,
    raw_event: &RocStr,
) {
    let method_ = method.to_string();
    let url_ = resolve_url(url);
    let raw_event_ = raw_event.clone();
    let headers_: Vec<(String, String)> = headers
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();

    wasm_bindgen_futures::spawn_local(async move {
        let body = match file_body(file_id, start, len) {
            Ok(b) => b,
            Err(e) => {
                let payload = format!("{{\"err\":\"{}\"}}", escape_json_string(&e));
                roc_run_event(&raw_event_, &RocList::from_slice(payload.as_bytes()));
                return;
            }
        };
        let result = fetch(&method_, &url_, body, &headers_).await;
        roc_run_event(&raw_event_, &RocList::from_slice(result.as_bytes()));
    });
}

/// Body for a fetch request.
enum FetchBody {
    None,
    Bytes(Vec<u8>),
    Blob(web_sys::Blob),
}

/// Resolve a file handle + range into a FetchBody::Blob.
fn file_body(file_id: u32, start: u64, len: u64) -> Result<FetchBody, String> {
    let file = FILE_STORE.with(|store| {
        store.borrow().get(&file_id).cloned()
    }).ok_or_else(|| format!("File with id {} not found", file_id))?;

    let blob: web_sys::Blob = if len == 0 {
        file.into()
    } else {
        file.slice_with_f64_and_f64(start as f64, (start + len) as f64)
            .map_err(|_| format!("Failed to slice file {} at {}+{}", file_id, start, len))?
    };

    Ok(FetchBody::Blob(blob))
}

/// Send an HTTP request using the browser fetch API. Returns a JSON string
/// in the format `{"ok":{"status":200,"body":[...]}}` or `{"err":"message"}`.
async fn fetch(
    method: &str,
    url: &str,
    body: FetchBody,
    headers: &[(String, String)],
) -> String {
    match fetch_impl(method, url, body, headers).await {
        Ok(json) => json,
        Err(e) => format!("{{\"err\":\"{}\"}}", escape_json_string(&e)),
    }
}

async fn fetch_impl(
    method: &str,
    url: &str,
    body: FetchBody,
    headers: &[(String, String)],
) -> Result<String, String> {
    use wasm_bindgen::JsCast;

    let opts = web_sys::RequestInit::new();
    opts.set_method(method);

    match body {
        FetchBody::None => {}
        FetchBody::Bytes(bytes) => {
            let array = web_sys::js_sys::Uint8Array::from(bytes.as_slice());
            opts.set_body(&array);
        }
        FetchBody::Blob(blob) => {
            opts.set_body(&blob);
        }
    }

    let request = web_sys::Request::new_with_str_and_init(url, &opts)
        .map_err(|_| format!("Failed to create request for {}", url))?;

    for (key, value) in headers {
        request.headers().set(key, value)
            .map_err(|_| format!("Failed to set header {}: {}", key, value))?;
    }

    let window = web_sys::window().ok_or("no window")?;
    let resp_js = wasm_bindgen_futures::JsFuture::from(window.fetch_with_request(&request))
        .await
        .map_err(|e| format!("Fetch failed: {:?}", e))?;

    let response: web_sys::Response = resp_js.dyn_into()
        .map_err(|_| "Response is not a Response object".to_string())?;

    let status = response.status();

    let body_buffer = wasm_bindgen_futures::JsFuture::from(
        response.array_buffer().map_err(|_| "Failed to read response body")?
    )
    .await
    .map_err(|_| "Failed to await response body".to_string())?;

    let body_array = web_sys::js_sys::Uint8Array::new(&body_buffer);
    let body_bytes = body_array.to_vec();
    let body_json = body_bytes
        .iter()
        .map(|b| b.to_string())
        .collect::<Vec<_>>()
        .join(",");

    Ok(format!(
        "{{\"ok\":{{\"status\":{},\"body\":[{}]}}}}",
        status, body_json
    ))
}

fn resolve_url(url: &RocStr) -> String {
    if url.starts_with('/') {
        format!(
            "{}{}",
            web_sys::window().expect("must have `window`").origin(),
            url
        )
    } else {
        url.to_string()
    }
}

// Minimal JSON string escaper to avoid pulling in serde and thereby increasing asset size.
fn escape_json_string(s: &str) -> String {
    s.chars()
        .flat_map(|c| match c {
            '"' => "\\\"".chars().collect::<Vec<_>>(),
            '\\' => "\\\\".chars().collect::<Vec<_>>(),
            '\n' => "\\n".chars().collect::<Vec<_>>(),
            '\r' => "\\r".chars().collect::<Vec<_>>(),
            '\t' => "\\t".chars().collect::<Vec<_>>(),
            c if c.is_control() => format!("\\u{:04x}", c as u32).chars().collect(),
            c => vec![c],
        })
        .collect()
}

// Keyboard

fn keyboard_add_global_listener_impl(event_name: &RocStr, key_filter: &RocList<RocStr>, prevent_default: bool) {
    use wasm_bindgen::JsCast;

    let event_name_clone = event_name.clone();
    let key_filter_vec: Vec<String> = key_filter.iter().map(|s| s.to_string()).collect();

    let closure = Closure::<dyn FnMut(web_sys::KeyboardEvent)>::new(move |e: web_sys::KeyboardEvent| {
        let key = e.key();

        // Filter keys: if filter is empty, allow all keys; otherwise only allow keys in the filter
        let should_trigger = key_filter_vec.is_empty() || key_filter_vec.contains(&key);

        if should_trigger {
            if prevent_default {
                e.prevent_default();
            }
            // Send the keyboard event with the key as payload
            roc_run_event(&event_name_clone, &RocList::from_slice(key.as_bytes()));
        }
    });

    let window = web_sys::window().expect("No global `window` exists");
    let document = window
        .document()
        .expect("Should have a `document` on `window`");

    document
        .add_event_listener_with_callback("keydown", closure.as_ref().unchecked_ref())
        .expect("Failed to add keydown event listener");

    // Keep the closure alive by leaking it
    closure.forget();
}

#[no_mangle]
pub extern "C" fn roc_fx_keyboard_add_global_listener(event_name: &RocStr, key_filter: &RocList<RocStr>) {
    keyboard_add_global_listener_impl(event_name, key_filter, false);
}

#[no_mangle]
pub extern "C" fn roc_fx_keyboard_add_global_listener_prevent_default(event_name: &RocStr, key_filter: &RocList<RocStr>) {
    keyboard_add_global_listener_impl(event_name, key_filter, true);
}

// Time

#[no_mangle]
pub extern "C" fn roc_fx_time_after(delay_ms: u32, raw_event: &RocStr) -> i32 {
    let window = web_sys::window().expect("No global `window` exists");
    let raw_event_clone = raw_event.clone();

    let closure = Closure::once_into_js(move || {
        roc_run_event(&raw_event_clone, &RocList::empty());
    });

    window
        .set_timeout_with_callback_and_timeout_and_arguments_0(
            closure.as_ref().unchecked_ref(),
            delay_ms as i32,
        )
        .expect("Failed to set timeout")
}

#[no_mangle]
pub extern "C" fn roc_fx_time_every(interval_ms: u32, raw_event: &RocStr) -> i32 {
    let window = web_sys::window().expect("No global `window` exists");
    let raw_event_clone = raw_event.clone();

    let closure = Closure::<dyn Fn()>::new(move || {
        roc_run_event(&raw_event_clone, &RocList::empty());
    });

    let timer_id = window
        .set_interval_with_callback_and_timeout_and_arguments_0(
            closure.as_ref().unchecked_ref(),
            interval_ms as i32,
        )
        .expect("Failed to set interval");

    // Keep the closure alive by leaking it (for repeating timers)
    closure.forget();

    timer_id
}

#[no_mangle]
pub extern "C" fn roc_fx_time_debounce(key: &RocStr, delay_ms: u32, raw_event: &RocStr) {
    let window = web_sys::window().expect("No global `window` exists");
    let key_string = key.to_string();

    // Cancel previous timer with the same key if it exists
    {
        let timers = DEBOUNCE_TIMERS.lock().unwrap();
        if let Some(&timer_id) = timers.get(&key_string) {
            window.clear_timeout_with_handle(timer_id);
        }
    }

    // Set new timer
    let raw_event_clone = raw_event.clone();
    let key_clone = key_string.clone();
    let closure = Closure::once_into_js(move || {
        // Remove timer from map and trigger event
        DEBOUNCE_TIMERS.lock().unwrap().remove(&key_clone);
        roc_run_event(&raw_event_clone, &RocList::empty());
    });

    let timer_id = window
        .set_timeout_with_callback_and_timeout_and_arguments_0(
            closure.as_ref().unchecked_ref(),
            delay_ms as i32,
        )
        .expect("Failed to set timeout");

    // Store timer ID for potential cancellation
    DEBOUNCE_TIMERS.lock().unwrap().insert(key_string, timer_id);
}

#[no_mangle]
pub extern "C" fn roc_fx_time_cancel(timer_id: i32) {
    let window = web_sys::window().expect("No global `window` exists");
    window.clear_timeout_with_handle(timer_id);
    window.clear_interval_with_handle(timer_id);
}

// File hashing

fn bytes_to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

fn hash_size_for_algorithm(algorithm: &str) -> usize {
    match algorithm {
        "SHA-1" => 20,
        "SHA-256" => 32,
        "SHA-384" => 48,
        "SHA-512" => 64,
        other => panic!("Unknown hash algorithm: {}", other),
    }
}

// ---------------------------------------------------------------------------
// File chunk hashing via Web Workers + SubtleCrypto
// ---------------------------------------------------------------------------

#[wasm_bindgen(inline_js = r#"
export function hashFileChunks(file, algorithm, chunkSize, workerCount, hashSize, onChunkHashed) {
    return new Promise((resolve, reject) => {
        const totalChunks = Math.ceil(file.size / chunkSize);

        if (totalChunks === 0) {
            crypto.subtle.digest(algorithm, new Uint8Array(0)).then((emptyHash) => {
                resolve({
                    totalChunks: 0,
                    hashOfChunkHashes: new Uint8Array(emptyHash),
                });
            });
            return;
        }

        const effectiveWorkers = Math.min(workerCount, totalChunks);

        const workerSrc = `
self.onmessage = async (e) => {
  const { index, blob, algorithm } = e.data;
  const buf = await blob.arrayBuffer();
  const hash = await crypto.subtle.digest(algorithm, buf);
  self.postMessage({ index, hash }, [hash]);
};`;

        const workerUrl = URL.createObjectURL(
            new Blob([workerSrc], { type: "application/javascript" })
        );
        const workers = Array.from({ length: effectiveWorkers }, () => new Worker(workerUrl));

        // Accumulate chunk hashes in order for computing hash_of_chunk_hashes at the end.
        const allChunkHashes = new Uint8Array(totalChunks * hashSize);
        let assigned = 0;
        let completed = 0;

        const assignNext = (worker) => {
            if (assigned >= totalChunks) return;
            const index = assigned++;
            const start = index * chunkSize;
            const end = Math.min(start + chunkSize, file.size);
            worker.postMessage({ index, blob: file.slice(start, end), algorithm });
        };

        const cleanup = () => {
            workers.forEach((w) => w.terminate());
            URL.revokeObjectURL(workerUrl);
        };

        workers.forEach((worker) => {
            worker.onmessage = (e) => {
                const hashBytes = new Uint8Array(e.data.hash);
                const index = e.data.index;
                allChunkHashes.set(hashBytes, index * hashSize);
                completed++;

                const startsAtByte = index * chunkSize;
                const endsAtByte = Math.min(startsAtByte + chunkSize, file.size);

                try { onChunkHashed(index, hashBytes, totalChunks, startsAtByte, endsAtByte); } catch (err) {
                    console.error("Crypto.hash_file_chunks! chunk event error:", err);
                }

                if (completed === totalChunks) {
                    cleanup();
                    crypto.subtle.digest(algorithm, allChunkHashes).then((combinedHash) => {
                        resolve({
                            totalChunks,
                            hashOfChunkHashes: new Uint8Array(combinedHash),
                        });
                    });
                } else {
                    assignNext(worker);
                }
            };
            worker.onerror = (err) => {
                cleanup();
                reject(new Error(err.message || "Worker error"));
            };
        });

        workers.forEach(assignNext);
    });
}
"#)]
extern "C" {
    #[wasm_bindgen(js_name = hashFileChunks)]
    fn hash_file_chunks_js(
        file: &web_sys::File,
        algorithm: &str,
        chunk_size: f64,
        worker_count: u32,
        hash_size: u32,
        on_chunk_hashed: &web_sys::js_sys::Function,
    ) -> web_sys::js_sys::Promise;
}

#[no_mangle]
pub extern "C" fn roc_fx_crypto_hash_file_chunks(
    file_id: u32,
    algorithm: &RocStr,
    chunk_size: u64,
    worker_count: i64,
    chunk_event: &RocStr,
    done_event: &RocStr,
) {
    let algorithm_ = algorithm.to_string();
    let chunk_event_ = chunk_event.clone();
    let done_event_ = done_event.clone();

    let chunk_size: u64 = std::cmp::max(chunk_size, 1);
    let hash_size = hash_size_for_algorithm(&algorithm_) as u32;

    // 0 = UseAllCores (from Roc Parallelism tag), positive = Exact(n)
    let worker_count: u32 = if worker_count <= 0 {
        let hw = web_sys::js_sys::Reflect::get(
            &web_sys::js_sys::global(),
            &"navigator".into(),
        )
        .ok()
        .and_then(|nav| web_sys::js_sys::Reflect::get(&nav, &"hardwareConcurrency".into()).ok())
        .and_then(|v| v.as_f64())
        .unwrap_or(4.0) as u32;
        hw.max(1)
    } else {
        (worker_count as u32).max(1)
    };

    wasm_bindgen_futures::spawn_local(async move {
        let file = FILE_STORE.with(|store| store.borrow().get(&file_id).cloned());

        let Some(file) = file else {
            fire_hash_error(&done_event_, file_id, &format!("File with id {} not found", file_id));
            return;
        };

        // Per-chunk callback. Leaked via forget() because wasm_bindgen::Closure panics on
        // drop if JS still holds a reference. The leak is bounded: one closure per hash call.
        let chunk_event_for_closure = chunk_event_.clone();
        let file_id_for_closure = file_id;
        let on_chunk_hashed = wasm_bindgen::closure::Closure::<
            dyn FnMut(u32, web_sys::js_sys::Uint8Array, u32, f64, f64),
        >::new(
            move |chunk_index: u32,
                  hash_bytes: web_sys::js_sys::Uint8Array,
                  total_chunks: u32,
                  starts_at_byte: f64,
                  ends_at_byte: f64| {
                let hash_hex = bytes_to_hex(&hash_bytes.to_vec());
                let payload = format!(
                    "{{\"file_id\":{},\"total_chunks\":{},\"chunk\":{{\"index\":{},\"starts_at_byte\":{},\"ends_at_byte\":{},\"hash\":\"{}\"}}}}",
                    file_id_for_closure,
                    total_chunks,
                    chunk_index,
                    starts_at_byte as u64,
                    ends_at_byte as u64,
                    hash_hex,
                );
                roc_run_event(
                    &chunk_event_for_closure,
                    &RocList::from_slice(payload.as_bytes()),
                );
            },
        );

        let result = wasm_bindgen_futures::JsFuture::from(hash_file_chunks_js(
            &file,
            &algorithm_,
            chunk_size as f64,
            worker_count,
            hash_size,
            on_chunk_hashed.as_ref().unchecked_ref(),
        ))
        .await;

        on_chunk_hashed.forget();

        match result {
            Ok(val) => {
                let total_chunks = web_sys::js_sys::Reflect::get(&val, &"totalChunks".into())
                    .ok()
                    .and_then(|v| v.as_f64())
                    .map(|v| v as u32)
                    .unwrap_or(0);

                let hash_of_chunk_hashes_js =
                    web_sys::js_sys::Reflect::get(&val, &"hashOfChunkHashes".into());
                let hash_hex = match hash_of_chunk_hashes_js {
                    Ok(ref js_val) => bytes_to_hex(&web_sys::js_sys::Uint8Array::new(js_val).to_vec()),
                    Err(_) => {
                        fire_hash_error(&done_event_, file_id, "Missing hashOfChunkHashes in result");
                        return;
                    }
                };

                let payload = format!(
                    "{{\"file_id\":{},\"ok\":{{\"total_chunks\":{},\"hash_of_chunk_hashes\":\"{}\"}}}}",
                    file_id, total_chunks, hash_hex,
                );
                roc_run_event(&done_event_, &RocList::from_slice(payload.as_bytes()));
            }
            Err(e) => {
                fire_hash_error(&done_event_, file_id, &format!("{:?}", e));
            }
        }
    });
}

fn fire_hash_error(event: &RocStr, file_id: u32, msg: &str) {
    let payload = format!(
        "{{\"file_id\":{},\"err\":\"{}\"}}",
        file_id,
        escape_json_string(msg)
    );
    roc_run_event(event, &RocList::from_slice(payload.as_bytes()));
}
