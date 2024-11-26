use roc_std::{roc_refcounted_noop_impl, RocBox, RocList, RocRefcounted, RocStr};
use std::collections::HashMap;

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
    update: core::mem::ManuallyDrop<RocBox<()>>,
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

    pub fn get_model_for_update_variant(&mut self) -> RocBox<()> {
        match self.discriminant() {
            DiscriminantAction::None => panic!("no model for this Action type"),
            DiscriminantAction::Update => unsafe {
                core::mem::ManuallyDrop::take(&mut self.payload.update)
            },
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

pub fn roc_to_percy_attrs(
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
pub struct EventData {
    pub handler: RocList<u8>,
    pub name: RocStr,
}

impl RocRefcounted for EventData {
    fn inc(&mut self) {
        self.name.inc();
        self.handler.inc();
    }
    fn dec(&mut self) {
        self.name.dec();
        self.handler.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct ElementData {
    pub attrs: RocList<ElementAttrs>,
    pub events: RocList<EventData>,
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
pub struct HtmlElement {
    pub data: ElementData,
    pub children: RocList<Html>,
}

impl RocRefcounted for HtmlElement {
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
pub struct HtmlText {
    pub str: RocStr,
}

impl RocRefcounted for HtmlText {
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
pub enum DiscriminantHtml {
    Element = 0,
    None = 1,
    Text = 2,
}

roc_refcounted_noop_impl!(DiscriminantHtml);

#[repr(transparent)]
pub struct Html(*mut UnionHtml);

impl Html {
    pub fn discriminant(&self) -> DiscriminantHtml {
        let discriminants = {
            use DiscriminantHtml::*;

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

    fn unmasked_pointer(&self) -> *mut UnionHtml {
        debug_assert!(!self.0.is_null());

        let mask = match std::mem::size_of::<usize>() {
            4 => !0b011usize,
            8 => !0b111usize,
            _ => unreachable!(),
        };

        ((self.0 as usize) & mask) as *mut UnionHtml
    }

    pub fn ptr_read_union(&self) -> core::mem::ManuallyDrop<UnionHtml> {
        let ptr = self.unmasked_pointer();

        core::mem::ManuallyDrop::new(unsafe { std::ptr::read(ptr) })
    }

    pub fn as_percy_text_node(&self) -> percy_dom::VirtualNode {
        unsafe { percy_dom::VirtualNode::text(self.ptr_read_union().text.str.as_str()) }
    }
}

#[repr(C)]
pub union UnionHtml {
    pub element: core::mem::ManuallyDrop<HtmlElement>,
    pub none: (),
    pub text: core::mem::ManuallyDrop<HtmlText>,
}

impl RocRefcounted for Html {
    fn inc(&mut self) {
        match self.discriminant() {
            DiscriminantHtml::Element => unsafe {
                self.ptr_read_union().element.children.inc();
                self.ptr_read_union().element.data.inc();
            },
            DiscriminantHtml::Text => unsafe {
                self.ptr_read_union().text.str.inc();
            },
            DiscriminantHtml::None => {}
        }
    }
    fn dec(&mut self) {
        match self.discriminant() {
            DiscriminantHtml::Element => unsafe {
                self.ptr_read_union().element.children.dec();
                self.ptr_read_union().element.data.dec();
            },
            DiscriminantHtml::Text => unsafe {
                self.ptr_read_union().text.str.dec();
            },
            DiscriminantHtml::None => {}
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}
