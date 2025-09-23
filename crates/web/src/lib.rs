use roc_std::RocList;
use roc_std::RocStr;
use std::collections::HashMap;
use wasm_bindgen::prelude::*;

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

    pdom::set(percy_dom::PercyDom::new_hydrate_mount(
        initial_vnode,
        app_element,
    ));
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
    let attrs = roc_to_percy_attrs(&value.ptr_read_union().element.data.attrs);
    let mut events = percy_dom::event::Events::new();

    // TODO: Support more event types
    let mouse_event_callback = |raw_event: RocStr| {
        std::rc::Rc::new(std::cell::RefCell::new(
            move |_event: percy_dom::event::MouseEvent| {
                roc_run_event(&raw_event, &RocList::empty())
            },
        ))
    };
    let input_event_callback = |raw_event: RocStr| {
        let tag = tag.clone();
        std::rc::Rc::new(Closure::<dyn FnMut(web_sys::InputEvent)>::new(
            move |e: web_sys::InputEvent| {
                fn current_target<T>(event: web_sys::InputEvent) -> T
                where
                    T: wasm_bindgen::JsCast,
                {
                    event
                        .current_target()
                        .expect("must have a `current_target`")
                        .dyn_into::<T>()
                        .expect("failed to cast `current_target` into element type {T:?}")
                }

                // TODO: Should we support arbitrary elements with `contenteditable` or
                // `designMode`?
                let current_target_value = match tag.as_str() {
                    "input" => current_target::<web_sys::HtmlInputElement>(e).value(),
                    "textarea" => current_target::<web_sys::HtmlTextAreaElement>(e).value(),
                    "select" => current_target::<web_sys::HtmlSelectElement>(e).value(),
                    _ => panic!("Unsupported tag type for `InputEvent`: {tag}"),
                };

                roc_run_event(
                    &raw_event,
                    &RocList::from_slice(current_target_value.as_bytes()),
                )
            },
        ))
    };

    for event in value.ptr_read_union().element.data.events.into_iter() {
        let event_name = event.name.to_string();
        match event_name.as_str() {
            "onclick" => events.insert_mouse_event(
                event_name.into(),
                mouse_event_callback(event.handler.clone()),
            ),
            "oninput" => events.__insert_unsupported_signature(
                event_name.into(),
                input_event_callback(event.handler.clone()),
            ),
            "onchange" => events.__insert_unsupported_signature(
                event_name.into(),
                input_event_callback(event.handler.clone()),
            ),
            "onkeyup" => events.__insert_unsupported_signature(
                event_name.into(),
                input_event_callback(event.handler.clone()),
            ),
            "onkeydown" => events.__insert_unsupported_signature(
                event_name.into(),
                input_event_callback(event.handler.clone()),
            ),
            event_name => panic!("Unsupported event type: {event_name}"),
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

pub fn roc_to_percy_attrs(
    attrs: &RocList<roc::glue::Attribute>,
) -> HashMap<String, percy_dom::AttributeValue> {
    HashMap::from_iter(
        attrs
            .into_iter()
            .filter_map(|attr| match attr.discriminant() {
                roc::glue::DiscriminantAttribute::String => {
                    let attr_ = attr.borrow_string();
                    Some((
                        attr_.key.to_string(),
                        percy_dom::AttributeValue::String(attr_.value.to_string()),
                    ))
                }
                roc::glue::DiscriminantAttribute::Boolean => {
                    let attr_ = attr.borrow_boolean();
                    Some((
                        attr_.key.to_string(),
                        percy_dom::AttributeValue::Bool(attr_.value),
                    ))
                }
            }),
    )
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

// HTTP

#[no_mangle]
pub extern "C" fn roc_fx_http_get(uri: &RocStr, raw_event: &RocStr) {
    let uri_ = if uri.starts_with('/') {
        format!(
            "{}{}",
            web_sys::window().expect("must have `window`").origin(),
            uri
        )
    } else {
        uri.to_string()
    };
    let raw_event_ = raw_event.clone();

    wasm_bindgen_futures::spawn_local(async move {
        let response_or_error_bytes = match reqwest::get(uri_).await {
            Ok(response) => {
                let status = response.status().as_u16();
                match response.bytes().await {
                    Ok(bytes) => {
                        let body_json = bytes
                            .iter()
                            .map(|b| b.to_string())
                            .collect::<Vec<_>>()
                            .join(",");

                        format!(
                            "{{\"ok\":{{\"status\":{},\"body\":[{}]}}}}",
                            status, body_json
                        )
                    }
                    Err(e) => {
                        let msg = escape_json_string(&e.to_string());
                        format!("{{\"err\":\"{}\"}}", msg)
                    }
                }
            }
            Err(e) => {
                let msg = escape_json_string(&e.to_string());
                format!("{{\"err\":\"{}\"}}", msg)
            }
        };

        roc_run_event(&raw_event_, &RocList::from_slice(response_or_error_bytes.as_bytes()))
    });
}

#[no_mangle]
pub extern "C" fn roc_fx_http_post(url: &RocStr, body: &RocList<u8>, raw_event: &RocStr) {
    let url_ = if url.starts_with('/') {
        format!(
            "{}{}",
            web_sys::window().expect("must have `window`").origin(),
            url
        )
    } else {
        url.to_string()
    };
    let body_ = body.as_slice().to_vec();
    let raw_event_ = raw_event.clone();

    wasm_bindgen_futures::spawn_local(async move {
        let client = reqwest::Client::new();

        let response_or_error_bytes = match client.post(&url_).body(body_).send().await {
            Ok(response) => {
                let status = response.status().as_u16();
                match response.bytes().await {
                    Ok(bytes) => {
                        let body_json = bytes
                            .iter()
                            .map(|b| b.to_string())
                            .collect::<Vec<_>>()
                            .join(",");

                        format!(
                            "{{\"ok\":{{\"status\":{},\"body\":[{}]}}}}",
                            status, body_json
                        )
                    }
                    Err(e) => {
                        let msg = escape_json_string(&e.to_string());
                        format!("{{\"err\":\"{}\"}}", msg)
                    }
                }
            }
            Err(e) => {
                let msg = escape_json_string(&e.to_string());
                format!("{{\"err\":\"{}\"}}", msg)
            }
        };

        roc_run_event(
            &raw_event_,
            &RocList::from_slice(response_or_error_bytes.as_bytes()),
        )
    });
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

#[no_mangle]
pub extern "C" fn roc_fx_keyboard_add_global_listener(event_name: &RocStr, key_filter: &RocList<RocStr>) {
    use wasm_bindgen::JsCast;

    let event_name_clone = event_name.clone();
    let key_filter_vec: Vec<String> = key_filter.iter().map(|s| s.to_string()).collect();

    let closure = Closure::<dyn FnMut(web_sys::KeyboardEvent)>::new(move |e: web_sys::KeyboardEvent| {
        let key = e.key();

        // Filter keys: if filter is empty, allow all keys; otherwise only allow keys in the filter
        let should_trigger = key_filter_vec.is_empty() || key_filter_vec.contains(&key);

        if should_trigger {
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
