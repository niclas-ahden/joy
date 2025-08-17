use roc_std::{roc_refcounted_noop_impl, RocBox, RocList, RocRefcounted, RocStr};

// Action

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantAction {
    None = 0,
    Update = 1,
}

impl core::fmt::Debug for DiscriminantAction {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::None => f.write_str("Action::None"),
            Self::Update => f.write_str("Action::Update"),
        }
    }
}

roc_refcounted_noop_impl!(DiscriminantAction);

#[repr(C)]
pub struct RawAction {
    payload: [i32; 1],
    discriminant: u8,
}

const _SIZE_CHECK_ACTION: () = assert!(core::mem::size_of::<RawAction>() == 8);
const _ALIGN_CHECK_ACTION: () = assert!(core::mem::align_of::<RawAction>() == 4);

impl RawAction {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> DiscriminantAction {
        if self.discriminant == 0 {
            DiscriminantAction::None
        } else if self.discriminant == 1 {
            DiscriminantAction::Update
        } else {
            panic!("Unknown discriminant: {}", self.discriminant);
        }
    }

    pub fn unwrap_model(&mut self) -> RocBox<()> {
        if self.discriminant() == DiscriminantAction::Update {
            unsafe { std::mem::transmute::<[i32; 1], RocBox<()>>(self.payload) }
        } else {
            panic!("Expected Update, got {:?}", self.discriminant());
        }
    }
}

impl Drop for RawAction {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => self.payload.dec(),
        }
    }
}

impl RocRefcounted for RawAction {
    fn inc(&mut self) {
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => self.payload.inc(),
        }
    }
    fn dec(&mut self) {
        match self.discriminant() {
            DiscriminantAction::None => {}
            DiscriminantAction::Update => self.payload.dec(),
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}

impl std::fmt::Debug for RawAction {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self.discriminant() {
            DiscriminantAction::None => f.debug_struct("Action::None").finish(),
            DiscriminantAction::Update => f
                .debug_struct("Action::Update")
                .field("payload", &self.payload)
                .finish(),
        }
    }
}

// Attribute

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct BooleanAttr {
    pub key: roc_std::RocStr,
    pub value: bool,
}

impl roc_std::RocRefcounted for BooleanAttr {
    fn inc(&mut self) {
        self.key.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct StringAttr {
    pub key: roc_std::RocStr,
    pub value: roc_std::RocStr,
}

impl roc_std::RocRefcounted for StringAttr {
    fn inc(&mut self) {
        self.key.inc();
        self.value.inc();
    }
    fn dec(&mut self) {
        self.key.dec();
        self.value.dec();
    }
    fn is_refcounted() -> bool {
        true
    }
}

#[derive(Clone, Copy, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(u8)]
pub enum DiscriminantAttribute {
    Boolean = 0,
    String = 1,
}

impl core::fmt::Debug for DiscriminantAttribute {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::Boolean => f.write_str("DiscriminantAttribute::Boolean"),
            Self::String => f.write_str("DiscriminantAttribute::String"),
        }
    }
}

roc_refcounted_noop_impl!(DiscriminantAttribute);

#[repr(C, align(4))]
pub union UnionAttribute {
    boolean: core::mem::ManuallyDrop<BooleanAttr>,
    string: core::mem::ManuallyDrop<StringAttr>,
}

// TODO(@roc-lang): See https://github.com/roc-lang/roc/issues/6012
// const _SIZE_CHECK_UnionAttribute: () = assert!(core::mem::size_of::<UnionAttribute>() == 24);
const _ALIGN_CHECK_UNION_ATTRIBUTE: () = assert!(core::mem::align_of::<UnionAttribute>() == 4);

const _SIZE_CHECK_ATTRIBUTE: () = assert!(core::mem::size_of::<Attribute>() == 28);
const _ALIGN_CHECK_ATTRIBUTE: () = assert!(core::mem::align_of::<Attribute>() == 4);

impl Attribute {
    /// Returns which variant this tag union holds. Note that this never includes a payload!
    pub fn discriminant(&self) -> DiscriminantAttribute {
        unsafe {
            let bytes = core::mem::transmute::<&Self, &[u8; core::mem::size_of::<Self>()]>(self);

            core::mem::transmute::<u8, DiscriminantAttribute>(*bytes.as_ptr().add(24))
        }
    }
}

#[repr(C)]
pub struct Attribute {
    payload: UnionAttribute,
    discriminant: DiscriminantAttribute,
}

impl Clone for Attribute {
    fn clone(&self) -> Self {
        use DiscriminantAttribute::*;

        let payload = unsafe {
            match self.discriminant {
                Boolean => UnionAttribute {
                    boolean: self.payload.boolean.clone(),
                },
                String => UnionAttribute {
                    string: self.payload.string.clone(),
                },
            }
        };

        Self {
            discriminant: self.discriminant,
            payload,
        }
    }
}

impl core::fmt::Debug for Attribute {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        use DiscriminantAttribute::*;

        unsafe {
            match self.discriminant {
                Boolean => {
                    let field: &BooleanAttr = &self.payload.boolean;
                    f.debug_tuple("Attribute::Boolean").field(field).finish()
                }
                String => {
                    let field: &StringAttr = &self.payload.string;
                    f.debug_tuple("Attribute::String").field(field).finish()
                }
            }
        }
    }
}

impl Eq for Attribute {}

impl PartialEq for Attribute {
    fn eq(&self, other: &Self) -> bool {
        use DiscriminantAttribute::*;

        if self.discriminant != other.discriminant {
            return false;
        }

        unsafe {
            match self.discriminant {
                Boolean => self.payload.boolean == other.payload.boolean,
                String => self.payload.string == other.payload.string,
            }
        }
    }
}

impl Ord for Attribute {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.partial_cmp(other).unwrap()
    }
}

impl PartialOrd for Attribute {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        use DiscriminantAttribute::*;

        use std::cmp::Ordering::*;

        match self.discriminant.cmp(&other.discriminant) {
            Less => Option::Some(Less),
            Greater => Option::Some(Greater),
            Equal => unsafe {
                match self.discriminant {
                    Boolean => self.payload.boolean.partial_cmp(&other.payload.boolean),
                    String => self.payload.string.partial_cmp(&other.payload.string),
                }
            },
        }
    }
}

impl core::hash::Hash for Attribute {
    fn hash<H: core::hash::Hasher>(&self, state: &mut H) {
        use DiscriminantAttribute::*;

        unsafe {
            match self.discriminant {
                Boolean => self.payload.boolean.hash(state),
                String => self.payload.string.hash(state),
            }
        }
    }
}

impl Attribute {
    pub fn unwrap_boolean(mut self) -> BooleanAttr {
        debug_assert_eq!(self.discriminant, DiscriminantAttribute::Boolean);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.boolean) }
    }

    pub fn borrow_boolean(&self) -> &BooleanAttr {
        debug_assert_eq!(self.discriminant, DiscriminantAttribute::Boolean);
        use core::borrow::Borrow;
        unsafe { self.payload.boolean.borrow() }
    }

    pub fn borrow_mut_boolean(&mut self) -> &mut BooleanAttr {
        debug_assert_eq!(self.discriminant, DiscriminantAttribute::Boolean);
        use core::borrow::BorrowMut;
        unsafe { self.payload.boolean.borrow_mut() }
    }

    pub fn unwrap_string(mut self) -> StringAttr {
        debug_assert_eq!(self.discriminant, DiscriminantAttribute::String);
        unsafe { core::mem::ManuallyDrop::take(&mut self.payload.string) }
    }

    pub fn borrow_string(&self) -> &StringAttr {
        debug_assert_eq!(self.discriminant, DiscriminantAttribute::String);
        use core::borrow::Borrow;
        unsafe { self.payload.string.borrow() }
    }

    pub fn borrow_mut_string(&mut self) -> &mut StringAttr {
        debug_assert_eq!(self.discriminant, DiscriminantAttribute::String);
        use core::borrow::BorrowMut;
        unsafe { self.payload.string.borrow_mut() }
    }
}

impl Attribute {
    pub fn boolean(payload: BooleanAttr) -> Self {
        Self {
            discriminant: DiscriminantAttribute::Boolean,
            payload: UnionAttribute {
                boolean: core::mem::ManuallyDrop::new(payload),
            },
        }
    }

    pub fn string(payload: StringAttr) -> Self {
        Self {
            discriminant: DiscriminantAttribute::String,
            payload: UnionAttribute {
                string: core::mem::ManuallyDrop::new(payload),
            },
        }
    }
}

impl Drop for Attribute {
    fn drop(&mut self) {
        // Drop the payloads
        match self.discriminant() {
            DiscriminantAttribute::Boolean => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.boolean)
            },
            DiscriminantAttribute::String => unsafe {
                core::mem::ManuallyDrop::drop(&mut self.payload.string)
            },
        }
    }
}

impl roc_std::RocRefcounted for Attribute {
    fn inc(&mut self) {
        unimplemented!();
    }
    fn dec(&mut self) {
        unimplemented!();
    }
    fn is_refcounted() -> bool {
        true
    }
}

// Event

#[derive(Clone, Default, Debug, PartialEq, PartialOrd, Eq, Ord, Hash)]
#[repr(C)]
pub struct EventData {
    pub handler: RocStr,
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
    pub attrs: RocList<Attribute>,
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

#[derive(Clone)]
#[repr(C)]
pub struct HtmlVoidElement {
    pub data: ElementData,
}

impl RocRefcounted for HtmlVoidElement {
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
    VoidElement = 3,
}

roc_refcounted_noop_impl!(DiscriminantHtml);

#[repr(transparent)]
pub struct Html(*mut UnionHtml);

const _SIZE_CHECK_HTML: () = assert!(core::mem::size_of::<Html>() == 4);
const _ALIGN_CHECK_HTML: () = assert!(core::mem::align_of::<Html>() == 4);

impl Html {
    pub fn discriminant(&self) -> DiscriminantHtml {
        let discriminants = {
            use DiscriminantHtml::*;
            [Element, None, Text, VoidElement]
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
}

impl std::fmt::Display for Html {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        unsafe {
            let ptr = self.unmasked_pointer();
            match self.discriminant() {
                DiscriminantHtml::Element => {
                    let element = &(*ptr).element;
                    let tag = element.data.tag.as_str();

                    write!(f, "<{}>", tag)?;

                    for (i, child) in element.children.iter().enumerate() {
                        if i > 0 {
                            write!(f, " ")?;
                        }
                        write!(f, "{}", child)?;
                    }

                    write!(f, "</{}>", tag)
                }
                DiscriminantHtml::VoidElement => {
                    let element = &(*ptr).element;
                    let tag = element.data.tag.as_str();
                    write!(f, "<{} />", tag)
                }
                DiscriminantHtml::None => write!(f, "Html::None"),
                DiscriminantHtml::Text => {
                    let text = &(*ptr).text;
                    let bytes = text.str.as_str().as_bytes();
                    // Convert to ASCII string, stopping at first null byte
                    let ascii_str: String = bytes
                        .iter()
                        .take_while(|&&b| b != 0)
                        .map(|&b| b as char)
                        .collect();
                    write!(f, "{}", ascii_str)
                }
            }
        }
    }
}

impl core::fmt::Debug for Html {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self.discriminant() {
            DiscriminantHtml::Element => {
                let payload_union = self.ptr_read_union();

                unsafe {
                    f.debug_tuple("Html::Element")
                        .field(&payload_union.element.data)
                        .field(&payload_union.element.children)
                        .finish()
                }
            }
            DiscriminantHtml::VoidElement => {
                let payload_union = self.ptr_read_union();

                unsafe {
                    f.debug_tuple("Html::VoidElement")
                        .field(&payload_union.element.data)
                        .finish()
                }
            }
            DiscriminantHtml::None => f.debug_tuple("Html::None").finish(),
            DiscriminantHtml::Text => {
                let payload_union = self.ptr_read_union();

                unsafe {
                    let text = &payload_union.text;
                    let bytes = text.str.as_str().as_bytes();
                    let safe_str: String = bytes
                        .iter()
                        .take_while(|&&b| b != 0)
                        .map(|&b| b as char)
                        .collect();
                    f.debug_tuple("Html::Text").field(&safe_str).finish()
                }
            }
        }
    }
}

#[repr(C)]
pub union UnionHtml {
    pub element: core::mem::ManuallyDrop<HtmlElement>,
    pub void_element: core::mem::ManuallyDrop<HtmlVoidElement>,
    pub none: (),
    pub text: core::mem::ManuallyDrop<HtmlText>,
}

impl RocRefcounted for Html {
    fn inc(&mut self) {
        unsafe {
            let ptr = self.unmasked_pointer();
            match self.discriminant() {
                DiscriminantHtml::Element => {
                    let element = &mut (*ptr).element;
                    element.children.inc();
                    element.data.inc();
                }
                DiscriminantHtml::VoidElement => {
                    let element = &mut (*ptr).element;
                    element.data.inc();
                }
                DiscriminantHtml::Text => {
                    let text = &mut (*ptr).text;
                    text.str.inc();
                }
                DiscriminantHtml::None => {}
            }
        }
    }
    fn dec(&mut self) {
        unsafe {
            let ptr = self.unmasked_pointer();
            match self.discriminant() {
                DiscriminantHtml::Element => {
                    let element = &mut (*ptr).element;
                    element.children.dec();
                    element.data.dec();
                }
                DiscriminantHtml::VoidElement => {
                    let element = &mut (*ptr).element;
                    element.data.dec();
                }
                DiscriminantHtml::Text => {
                    let text = &mut (*ptr).text;
                    text.str.dec();
                }
                DiscriminantHtml::None => {}
            }
        }
    }
    fn is_refcounted() -> bool {
        true
    }
}
