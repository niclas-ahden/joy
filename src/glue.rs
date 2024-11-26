use roc_std::{roc_refcounted_noop_impl, RocBox, RocList, RocRefcounted, RocStr};
use std::collections::HashMap;

use crate::console;

#[repr(C)]
pub struct Return {
    pub elem: Elem,
    pub model: RocBox<()>,
}

impl RocRefcounted for Return {
    fn inc(&mut self) {
        self.elem.inc();
        self.model.inc();
    }
    fn dec(&mut self) {
        self.elem.dec();
        self.model.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[repr(transparent)]
pub struct ElemDiv {
    pub data: Elem,
}

impl RocRefcounted for ElemDiv {
    fn inc(&mut self) {
        self.data.inc();
    }
    fn dec(&mut self) {
        self.data.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(transparent)]
pub struct ElemText {
    pub str: RocStr,
}

impl RocRefcounted for ElemText {
    fn inc(&mut self) {
        self.str.inc();
    }
    fn dec(&mut self) {
        self.str.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantElem {
    Div = 0,
    Text = 1,
}

roc_refcounted_noop_impl!(DiscriminantElem);

#[repr(transparent)]
pub struct Elem(*mut UnionElem);

impl Elem {
    pub fn discriminant(&self) -> DiscriminantElem {
        let discriminants = {
            use DiscriminantElem::*;

            [Div, Text]
        };

        if self.0.is_null() {
            unreachable!("this pointer cannot be NULL")
        } else {
            match std::mem::size_of::<usize>() {
                4 => discriminants[self.0 as usize & 0b011],
                8 => discriminants[self.0 as usize & 0b111],
                _ => unreachable!(),
            }
        }
    }

    fn unmasked_pointer(&self) -> *mut UnionElem {
        debug_assert!(!self.0.is_null());

        let mask = match std::mem::size_of::<usize>() {
            4 => !0b011usize,
            8 => !0b111usize,
            _ => unreachable!(),
        };

        ((self.0 as usize) & mask) as *mut UnionElem
    }

    unsafe fn ptr_read_union(&self) -> core::mem::ManuallyDrop<UnionElem> {
        let ptr = self.unmasked_pointer();

        core::mem::ManuallyDrop::new(unsafe { std::ptr::read(ptr) })
    }
}

#[repr(C)]
union UnionElem {
    div: core::mem::ManuallyDrop<ElemDiv>,
    text: core::mem::ManuallyDrop<ElemText>,
}

impl RocRefcounted for Elem {
    fn inc(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantElem::Div => {
                    let mut union = self.ptr_read_union();
                    (*union.div).inc();
                }
                DiscriminantElem::Text => {
                    let mut union = self.ptr_read_union();
                    (*union.text).inc();
                }
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            match self.discriminant() {
                DiscriminantElem::Div => {
                    let mut union = self.ptr_read_union();
                    (*union.div).dec();
                }
                DiscriminantElem::Text => {
                    let mut union = self.ptr_read_union();
                    (*union.text).dec();
                }
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl std::fmt::Display for Elem {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        unsafe {
            match self.discriminant() {
                DiscriminantElem::Div => {
                    write!(f, "Div ")?;

                    // write content of Div
                    let union = self.ptr_read_union();
                    write!(f, "{}", (*union.div).data)
                }
                DiscriminantElem::Text => {
                    let union = self.ptr_read_union();
                    write!(f, "{}", (*union.text).str.as_str())
                }
            }
        }
    }
}

impl From<&Elem> for percy_dom::VirtualNode {
    fn from(value: &Elem) -> percy_dom::VirtualNode {
        unsafe {
            match value.discriminant() {
                DiscriminantElem::Div => {
                    let children = vec![percy_dom::VirtualNode::from(
                        &(*value.ptr_read_union().div).data,
                    )];

                    let mut events = percy_dom::event::Events::new();

                    use std::cell::RefCell;
                    use std::rc::Rc;

                    let callback = Rc::new(RefCell::new(|event: percy_dom::event::MouseEvent| {
                        console::log(
                            format!("Mouse event received! {}", event.to_string()).as_str(),
                        );
                    }));

                    events.insert_mouse_event("onclick".into(), callback);

                    percy_dom::VirtualNode::Element(percy_dom::VElement {
                        tag: "div".to_string(),
                        attrs: HashMap::default(),
                        events,
                        children,
                        special_attributes: percy_dom::SpecialAttributes::default(),
                    })
                }
                DiscriminantElem::Text => percy_dom::VirtualNode::Text(percy_dom::VText {
                    text: (*value.ptr_read_union().text).str.as_str().to_string(),
                }),
            }
        }
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantAction {
    None = 0,
    Update = 1,
}

roc_refcounted_noop_impl!(DiscriminantAction);

#[repr(C, align(8))]
pub union UnionAction {
    none: (),
    update: core::mem::ManuallyDrop<RocList<u8>>,
}

#[repr(C)]
pub struct Action {
    payload: UnionAction,
    discriminant: DiscriminantAction,
}

impl Action {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> DiscriminantAction {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, DiscriminantAction>(*bytes.as_ptr().add(24))
        }
    }
}

impl core::fmt::Debug for Action {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use DiscriminantAction::*;
        match self.discriminant {
            None => f.write_str("Action::None"),
            Update => f.write_str("Action::Update"),
        }
    }
}

impl Drop for Action {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.update)
            },
        }
    }
}

impl RocRefcounted for Action {
    fn inc(&mut self) {
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => unsafe {
                (*self.payload.update).inc();
            },
        }
    }
    fn dec(&mut self) {
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => unsafe {
                (*self.payload.update).dec();
            },
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ElementAttrs {
    pub key: RocStr,
    pub val: RocStr,
}

fn roc_to_percy_attrs(
    values: &RocList<ElementAttrs>,
) -> HashMap<String, percy_dom::AttributeValue> {
    HashMap::from_iter(values.into_iter().map(|attr| {
        (
            attr.key.as_str().to_string(),
            percy_dom::AttributeValue::String(attr.val.as_str().to_string()),
        )
    }))
}

impl RocRefcounted for ElementAttrs {
    fn inc(&mut self) {
        self.key.inc();
        self.val.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
        self.val.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ElementData {
    pub attrs: RocList<ElementAttrs>,
    pub events: RocList<u64>,
    pub tag: RocStr,
}

impl RocRefcounted for ElementData {
    fn inc(&mut self) {
        self.attrs.inc();
        self.events.inc();
        self.tag.inc();
    }
    fn dec(&mut self) {
        self.attrs.dec();
        self.events.dec();
        self.tag.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone)]
#[repr(C)]
pub struct HtmlForHostElement {
    pub data: ElementData,
    pub children: RocList<HtmlForHost>,
}

impl RocRefcounted for HtmlForHostElement {
    fn inc(&mut self) {
        self.data.inc();
        self.children.inc();
    }
    fn dec(&mut self) {
        self.data.dec();
        self.children.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(transparent)]
pub struct HtmlForHostText {
    pub str: RocStr,
}

impl RocRefcounted for HtmlForHostText {
    fn inc(&mut self) {
        self.str.inc();
    }
    fn dec(&mut self) {
        self.str.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum DiscriminantHtmlForHost {
    Element = 0,
    None = 1,
    Text = 2,
}

roc_refcounted_noop_impl!(DiscriminantHtmlForHost);

#[repr(transparent)]
pub struct HtmlForHost(*mut UnionHtmlForHost);

impl HtmlForHost {
    pub fn discriminant(&self) -> DiscriminantHtmlForHost {
        let discriminants = {
            use DiscriminantHtmlForHost::*;

            [Element, None, Text]
        };

        if self.0.is_null() {
            discriminants[1]
        } else {
            match std::mem::size_of::<usize>() {
                4 => discriminants[self.0 as usize & 0b011],
                8 => discriminants[self.0 as usize & 0b111],
                _ => unreachable!(),
            }
        }
    }

    fn unmasked_pointer(&self) -> *mut UnionHtmlForHost {
        debug_assert!(!self.0.is_null());

        let mask = match std::mem::size_of::<usize>() {
            4 => !0b011usize,
            8 => !0b111usize,
            _ => unreachable!(),
        };

        ((self.0 as usize) & mask) as *mut UnionHtmlForHost
    }

    unsafe fn ptr_read_union(&self) -> core::mem::ManuallyDrop<UnionHtmlForHost> {
        let ptr = self.unmasked_pointer();

        core::mem::ManuallyDrop::new(unsafe { std::ptr::read(ptr) })
    }
}

#[repr(C)]
union UnionHtmlForHost {
    element: core::mem::ManuallyDrop<HtmlForHostElement>,
    none: (),
    text: core::mem::ManuallyDrop<HtmlForHostText>,
}

impl RocRefcounted for HtmlForHost {
    fn inc(&mut self) {
        match self.discriminant() {
            DiscriminantHtmlForHost::Element => unsafe {
                self.ptr_read_union().element.children.inc();
                self.ptr_read_union().element.data.inc();
            },
            DiscriminantHtmlForHost::Text => unsafe {
                self.ptr_read_union().text.str.inc();
            },
            DiscriminantHtmlForHost::None => {}
        }
    }
    fn dec(&mut self) {
        match self.discriminant() {
            DiscriminantHtmlForHost::Element => unsafe {
                self.ptr_read_union().element.children.dec();
                self.ptr_read_union().element.data.dec();
            },
            DiscriminantHtmlForHost::Text => unsafe {
                self.ptr_read_union().text.str.dec();
            },
            DiscriminantHtmlForHost::None => {}
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl From<&HtmlForHost> for percy_dom::VirtualNode {
    fn from(value: &HtmlForHost) -> percy_dom::VirtualNode {
        match value.discriminant() {
            DiscriminantHtmlForHost::Text => unsafe {
                percy_dom::VirtualNode::text(value.ptr_read_union().text.str.as_str())
            },
            DiscriminantHtmlForHost::Element => unsafe {
                let children = value
                    .ptr_read_union()
                    .element
                    .children
                    .into_iter()
                    .map(percy_dom::VirtualNode::from)
                    .collect();

                let tag = value.ptr_read_union().element.data.tag.as_str().to_owned();

                let attrs = roc_to_percy_attrs(&value.ptr_read_union().element.data.attrs);

                percy_dom::VirtualNode::Element(percy_dom::VElement {
                    tag,
                    attrs,
                    // TODO events
                    events: percy_dom::event::Events::new(),
                    children,
                    special_attributes: percy_dom::SpecialAttributes::default(),
                })
            },
            DiscriminantHtmlForHost::None => percy_dom::VirtualNode::text(""),
        }
    }
}

#[repr(C)]
pub struct PlatformState {
    pub boxed_model: RocBox<()>,
    pub handlers: RocList<()>,
    pub html_with_handler_ids: HtmlForHost,
}

impl RocRefcounted for PlatformState {
    fn inc(&mut self) {
        self.boxed_model.inc();
        self.handlers.inc();
        self.html_with_handler_ids.inc();
    }
    fn dec(&mut self) {
        self.boxed_model.dec();
        self.handlers.dec();
        self.html_with_handler_ids.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}
