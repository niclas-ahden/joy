use model::Model;
use roc_std::{RocList, RocRefcounted, RocStr};
use std::alloc::GlobalAlloc;
use std::alloc::Layout;
use std::os::raw::c_void;
use wasm_bindgen::prelude::*;
use web_sys::Document;

mod console;
mod glue;
mod model;
mod pdom;

#[global_allocator]
static WEE_ALLOC: wee_alloc::WeeAlloc = wee_alloc::WeeAlloc::INIT;

fn document() -> Option<Document> {
    web_sys::window().expect("should have a window").document()
}

// #[wasm_bindgen]
// pub fn app_update() {
//     let new_vnode: percy_dom::VirtualNode = MODEL.with_borrow_mut(|maybe_state| {
//         if let Some(model) = maybe_state {
//             let roc_return = roc_render(model.to_owned());

//             *maybe_state = Some(roc_return.model);

//             (&roc_return.elem).into()
//         } else {
//             percy_dom::VirtualNode::text("Loading...")
//         }
//     });

//     with_pdom(|pdom| {
//         pdom.update(new_vnode);
//     });
// }

#[wasm_bindgen]
pub fn app_init() {
    std::panic::set_hook(Box::new(console_error_panic_hook::hook));

    console::log("INFO: STARTING APP");

    let initial_vnode = model::with(|maybe_model| {
        let mut boxed_model = roc_init();

        let roc_html = roc_render(&mut boxed_model);

        let initial_vnode = roc_html_to_percy(&roc_html);

        *maybe_model = Some(boxed_model);

        initial_vnode
    });

    let app_node = document().unwrap().get_element_by_id("app").unwrap();

    pdom::set(percy_dom::PercyDom::new_replace_mount(
        initial_vnode,
        app_node,
    ));
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_alloc(size: usize, _alignment: u32) -> *mut c_void {
    let layout = Layout::from_size_align(size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.alloc(layout) as *mut c_void
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dealloc(c_ptr: *mut u8, _alignment: u32) {
    let layout =
        Layout::from_size_align(0, 8).unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.dealloc(c_ptr, layout);
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_realloc(
    c_ptr: *mut u8,
    new_size: usize,
    old_size: usize,
    _alignment: u32,
) -> *mut u8 {
    let layout = Layout::from_size_align(old_size, 8)
        .unwrap_or_else(|_| std::panic::panic_any("invalid layout"));

    WEE_ALLOC.realloc(c_ptr, layout, new_size)
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_panic(msg: &RocStr, _tag_id: u32) {
    panic!("ROC CRASHED {}", msg.as_str())
}

/// Currently not used, roc doesn't include `dbg` in `roc build --no-link` but we would like it to
///
/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_dbg(loc: &RocStr, msg: &RocStr) {
    eprintln!("[{}] {}", loc, msg);
}

/// # Safety
///
/// This function is unsafe.
#[no_mangle]
pub unsafe extern "C" fn roc_memset(dst: *mut c_void, c: i32, n: usize) -> *mut c_void {
    let slice = std::slice::from_raw_parts_mut(dst as *mut u8, n);
    for byte in slice {
        *byte = c as u8;
    }
    dst
}

pub fn roc_init() -> Model {
    #[link(name = "app")]
    extern "C" {
        // initForHost : I32 -> Model
        #[link_name = "roc__initForHost_1_exposed"]
        fn caller(arg_not_used: i32) -> Model;
    }

    console::log("CALLING ROC INIT");

    unsafe { caller(0) }
}

pub fn roc_update(state: &mut Model, raw_event: RocList<u8>) -> glue::Action {
    #[link(name = "app")]
    extern "C" {
        // updateForHost : Box Model, List U8 -> Action.Action (Box Model)
        #[link_name = "roc__updateForHost_1_exposed"]
        fn caller(state: &mut Model, raw_event: RocList<u8>) -> glue::Action;
    }

    console::log("CALLING ROC_UPDATE");

    unsafe { caller(state, raw_event) }
}

pub fn roc_render(model: &mut Model) -> glue::Html {
    #[link(name = "app")]
    extern "C" {
        // renderForHost : Box Model -> Html.Html Model
        #[link_name = "roc__renderForHost_1_exposed"]
        fn caller(model: &mut Model) -> glue::Html;
    }

    console::log("INCREMENT MODEL REF COUNT");

    // increment refcount so roc doesn't deallocate
    model.inc();

    console::log("CALLING ROC RENDER");

    unsafe { caller(model) }
}

#[no_mangle]
pub extern "C" fn roc_fx_log(msg: &RocStr) {
    console::log(msg.as_str());
}

fn roc_html_to_percy(value: &glue::Html) -> percy_dom::VirtualNode {
    match value.discriminant() {
        glue::DiscriminantHtml::None => percy_dom::VirtualNode::text(""),
        glue::DiscriminantHtml::Text => value.as_percy_text_node(),
        glue::DiscriminantHtml::Element => unsafe {
            let children: Vec<percy_dom::VirtualNode> = value
                .ptr_read_union()
                .element
                .children
                .into_iter()
                .map(roc_html_to_percy)
                .collect();

            let tag = value.ptr_read_union().element.data.tag.as_str().to_owned();

            let attrs = glue::roc_to_percy_attrs(&value.ptr_read_union().element.data.attrs);

            console::log(
                format!("EVENTS: {:?}", value.ptr_read_union().element.data.events).as_str(),
            );

            let mut events = percy_dom::event::Events::new();

            let callback = |raw_event: RocList<u8>| {
                let event_data = raw_event.clone(); // Clone the event data before moving into closure
                std::rc::Rc::new(std::cell::RefCell::new(
                    move |event: percy_dom::event::MouseEvent| {
                        console::log(
                            format!("Mouse event received! {}", event.to_string()).as_str(),
                        );

                        // model::with(|maybe_state| {
                        //     if let Some(state) = maybe_state {
                        //         let mut action = roc_update(state, event_data.clone());
                        //         match action.discriminant() {
                        //             glue::DiscriminantAction::None => {}
                        //             glue::DiscriminantAction::Update => {
                        //                 model::with(|maybe_model| {
                        //                     *maybe_model =
                        //                         Some(action.get_model_for_update_variant());
                        //                 })
                        //             }
                        //         }
                        //     }
                        // })
                    },
                ))
            };

            for event in value.ptr_read_union().element.data.events.into_iter() {
                let event_callback = callback(event.handler.clone());
                events.insert_mouse_event("onclick".into(), event_callback);
            }

            percy_dom::VirtualNode::Element(percy_dom::VElement {
                tag,
                attrs,
                events,
                children,
                special_attributes: percy_dom::SpecialAttributes::default(),
            })
        },
    }
}
