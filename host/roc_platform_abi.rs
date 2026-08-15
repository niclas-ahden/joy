//! Roc Platform ABI
//!
//! This file defines the Rust interface for hosted functions in a Roc platform.
//! It is committed and maintained by hand in the shape `roc glue` (Rust spec)
//! would emit: running `roc glue` on this platform overflows its stack, so
//! there is nothing to regenerate it with (see build.roc). When the platform
//! API changes, update the types here and rely on the size/alignment
//! assertions below to catch layout drift at compile time.
//!
//! Hosted argument ownership:
//! - Roc transfers ownership of refcounted arguments to the hosted function.
//! - The hosted function must decref owned refcounted arguments when done.
//! - If the host stores or returns an argument, it must retain or transfer ownership explicitly.
//!
//! Import this module from the platform host and implement the listed hosted symbols
//! with the exact natural C ABI signatures shown below.

#![cfg_attr(rustfmt, rustfmt_skip)]
#![allow(dead_code)]

use core::ffi::c_void;
use core::sync::atomic::{AtomicIsize, Ordering};

/// Runtime representation of an opaque `Box(T)` value.
pub type RocBox = *mut c_void;

/// Host-internal allocator and diagnostic context used by helper functions in this file.
///
/// Compiled Roc code does not receive this value. The real host ABI is the set of direct
/// linker symbols declared below (`roc_alloc`, hosted symbols, and provided entrypoints).
#[repr(C)]
pub struct RocHost {
    pub env: *mut c_void,
    pub roc_alloc: extern "C" fn(*mut RocHost, usize, usize) -> *mut c_void,
    pub roc_dealloc: extern "C" fn(*mut RocHost, *mut c_void, usize),
    pub roc_realloc: extern "C" fn(*mut RocHost, *mut c_void, usize, usize) -> *mut c_void,
    pub roc_dbg: extern "C" fn(*mut RocHost, *const u8, usize),
    pub roc_expect_failed: extern "C" fn(*mut RocHost, *const u8, usize),
    pub roc_crashed: extern "C" fn(*mut RocHost, *const u8, usize),
}

impl RocHost {
    /// Allocate memory with the given alignment and length.
    ///
    /// # Safety
    /// The returned pointer must be used only according to Roc allocation layout
    /// rules and later released through the matching host deallocator.
    #[inline]
    pub unsafe fn alloc(&self, alignment: usize, length: usize) -> *mut c_void {
        let host = self as *const RocHost as *mut RocHost;
        (self.roc_alloc)(host, length, alignment)
    }

    /// Deallocate memory previously allocated with `alloc`.
    ///
    /// # Safety
    /// `ptr` must have been allocated by this host with the same alignment and must
    /// not be used after this call.
    #[inline]
    pub unsafe fn dealloc(&self, ptr: *mut c_void, alignment: usize) {
        let host = self as *const RocHost as *mut RocHost;
        (self.roc_dealloc)(host, ptr, alignment);
    }

    /// Reallocate memory to a new size.
    ///
    /// # Safety
    /// `old_ptr` must have been allocated by this host with the same alignment.
    /// The returned pointer replaces `old_ptr`; the old pointer must not be used.
    #[inline]
    pub unsafe fn realloc(
        &self,
        old_ptr: *mut c_void,
        alignment: usize,
        new_length: usize,
    ) -> *mut c_void {
        let host = self as *const RocHost as *mut RocHost;
        (self.roc_realloc)(host, old_ptr, new_length, alignment)
    }
}

/// Uniform ABI function pointer stored in `RocErasedCallablePayload`.
///
/// The reuse argument is a reuse channel. A caller can hand over one owned
/// reference to the allocation holding the borrowed capture bytes, and the
/// callee consumes it exactly once. The host has none to give, so it passes
/// null.
///
/// The last argument is an out parameter: the callee writes the descriptor of
/// the bytes it returned there, or null when the result is descriptor-free.
/// Every callee writes it, so it must point at four writable bytes even though
/// the host has no use for the value: Joy's return layouts are static and
/// spelled out in this file. It is part of the wasm function type, so a call
/// that omits it traps as a signature mismatch rather than passing garbage.
pub type RocErasedCallableFn =
    extern "C" fn(*mut RocHost, *mut u8, *const u8, *mut u8, *mut u8, *mut RocBoxyDescriptor);

/// Descriptor of a returned value, opaque to the host.
pub type RocBoxyDescriptor = *const u8;

/// Final-drop callback for inline erased-callable captures.
pub type RocErasedCallableOnDrop = extern "C" fn(*mut u8, *mut RocHost);

/// Payload header for `Box(function)`.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RocErasedCallablePayload {
    pub callable_fn_ptr: RocErasedCallableFn,
    pub on_drop: Option<RocErasedCallableOnDrop>,
}

/// Runtime representation of `Box(function)`.
pub type RocErasedCallable = *mut u8;

pub const ROC_ERASED_CALLABLE_CAPTURE_ALIGNMENT: usize = 16;
pub const ROC_ERASED_CALLABLE_PAYLOAD_ALIGNMENT: usize = 16;
pub const ROC_ERASED_CALLABLE_CAPTURE_OFFSET: usize =
    (core::mem::size_of::<RocErasedCallablePayload>() + 15) & !15;

#[inline]
pub const fn roc_erased_callable_payload_size(capture_size: usize) -> usize {
    ROC_ERASED_CALLABLE_CAPTURE_OFFSET + capture_size
}

#[inline]
/// # Safety
/// `callable` must be a non-null Roc erased-callable data pointer.
pub unsafe fn roc_erased_callable_payload_ptr(callable: RocErasedCallable) -> *mut RocErasedCallablePayload {
    callable as *mut RocErasedCallablePayload
}

#[inline]
/// # Safety
/// `callable` must be a non-null Roc erased-callable data pointer.
pub unsafe fn roc_erased_callable_capture_ptr(callable: RocErasedCallable) -> *mut u8 {
    callable.add(ROC_ERASED_CALLABLE_CAPTURE_OFFSET)
}

/// Allocate a Roc erased callable payload.
///
/// # Safety
/// The caller must initialize and use the returned callable according to Roc's
/// erased-callable ABI. `callable_fn_ptr` and `on_drop` must have matching ABI
/// signatures for the captured payload.
pub unsafe fn roc_erased_callable_allocate(
    roc_host: &RocHost,
    callable_fn_ptr: RocErasedCallableFn,
    on_drop: Option<RocErasedCallableOnDrop>,
    capture_size: usize,
) -> RocErasedCallable {
    let ptr_width = core::mem::size_of::<usize>();
    let alignment = core::cmp::max(ptr_width, ROC_ERASED_CALLABLE_PAYLOAD_ALIGNMENT);
    let extra_bytes = core::cmp::max(ptr_width, ROC_ERASED_CALLABLE_PAYLOAD_ALIGNMENT);
    let base = roc_host.alloc(alignment, extra_bytes + roc_erased_callable_payload_size(capture_size)) as *mut u8;
    let data = base.add(extra_bytes);
    let rc = data.sub(core::mem::size_of::<isize>()) as *mut isize;
    *rc = 1;
    let payload = roc_erased_callable_payload_ptr(data);
    *payload = RocErasedCallablePayload { callable_fn_ptr, on_drop };
    data
}

/// Payload drop callback for a boxed value.
///
/// The callback receives the boxed payload data pointer and must recursively
/// decref any Roc refcounted values inside the payload. It must not free the
/// box allocation; `decref_box_with` and `free_box_with` free it after the callback.
pub type RocBoxPayloadDecref = extern "C" fn(*mut c_void, *mut RocHost);

/// Increment the refcount of a boxed payload data pointer.
pub fn incref_box(data_ptr: RocBox, amount: isize) {
    let data = match box_data_ptr(data_ptr) {
        Some(ptr) => ptr,
        None => return,
    };
    let rc = box_refcount_ptr(data);
    unsafe {
        if (*rc).load(Ordering::Relaxed) == 0 {
            return; // REFCOUNT_STATIC_DATA
        }
        (*rc).fetch_add(amount, Ordering::Relaxed);
    }
}

/// Allocate a Roc box and return a pointer to its payload data.
pub fn allocate_box(
    payload_size: usize,
    payload_alignment: usize,
    payload_contains_refcounted: bool,
    roc_host: &RocHost,
) -> RocBox {
    let ptr_width = core::mem::size_of::<usize>();
    let required_space = if payload_contains_refcounted { 2 * ptr_width } else { ptr_width };
    let header_bytes = required_space.max(payload_alignment);
    let alloc_alignment = ptr_width.max(payload_alignment);
    let base = unsafe { roc_host.alloc(alloc_alignment, header_bytes + payload_size) } as *mut u8;
    let data = unsafe { base.add(header_bytes) };
    unsafe {
        let rc = data.sub(core::mem::size_of::<isize>()) as *mut isize;
        *rc = 1;
    }
    data as RocBox
}

/// Decrement a pointer-aligned boxed payload with no Roc refcounted values.
pub fn decref_box(data_ptr: RocBox, roc_host: &RocHost) {
    decref_box_with(data_ptr, core::mem::align_of::<usize>(), false, None, roc_host);
}

/// Increment a boxed function closure.
pub fn incref_erased_callable(callable: RocErasedCallable, amount: isize) {
    incref_box(callable as RocBox, amount);
}

/// Decrement a boxed function closure and run its capture drop callback on final release.
pub fn decref_erased_callable(callable: RocErasedCallable, roc_host: &RocHost) {
    decref_box_with(
        callable as RocBox,
        ROC_ERASED_CALLABLE_PAYLOAD_ALIGNMENT,
        false,
        Some(drop_erased_callable_payload),
        roc_host,
    );
}

extern "C" fn drop_erased_callable_payload(data_ptr: *mut c_void, roc_host: *mut RocHost) {
    if data_ptr.is_null() || roc_host.is_null() {
        return;
    }
    unsafe {
        let callable = data_ptr as RocErasedCallable;
        let payload = roc_erased_callable_payload_ptr(callable);
        if let Some(on_drop) = (*payload).on_drop {
            on_drop(roc_erased_callable_capture_ptr(callable), roc_host);
        }
    }
}

/// Decrement a boxed payload and run payload teardown when this is the final ref.
///
/// `payload_contains_refcounted` must match the value passed to `allocate_box`:
/// it determines the box header size, and is independent of whether a
/// `payload_decref` teardown callback is supplied. A host resource handle such
/// as `Box(U64)` holding a raw pointer has `payload_contains_refcounted: false`
/// even when it provides a teardown callback to free the underlying resource.
pub fn decref_box_with(
    data_ptr: RocBox,
    payload_alignment: usize,
    payload_contains_refcounted: bool,
    payload_decref: Option<RocBoxPayloadDecref>,
    roc_host: &RocHost,
) {
    let data = match box_data_ptr(data_ptr) {
        Some(ptr) => ptr,
        None => return,
    };
    let rc = box_refcount_ptr(data);
    unsafe {
        if (*rc).load(Ordering::Relaxed) == 0 {
            return; // REFCOUNT_STATIC_DATA
        }
        let prev = (*rc).fetch_sub(1, Ordering::Relaxed);
        if prev == 1 {
            if let Some(callback) = payload_decref {
                callback(data_ptr, roc_host as *const RocHost as *mut RocHost);
            }
            free_box_allocation(data, payload_alignment, payload_contains_refcounted, roc_host);
        }
    }
}

/// Free a boxed payload allocation immediately after running payload teardown.
///
/// See `decref_box_with` for the meaning of `payload_contains_refcounted`.
pub fn free_box_with(
    data_ptr: RocBox,
    payload_alignment: usize,
    payload_contains_refcounted: bool,
    payload_decref: Option<RocBoxPayloadDecref>,
    roc_host: &RocHost,
) {
    let data = match box_data_ptr(data_ptr) {
        Some(ptr) => ptr,
        None => return,
    };
    if let Some(callback) = payload_decref {
        callback(data_ptr, roc_host as *const RocHost as *mut RocHost);
    }
    free_box_allocation(data, payload_alignment, payload_contains_refcounted, roc_host);
}

/// Return true when a boxed payload data pointer has exactly one live ref.
pub fn is_unique_box(data_ptr: RocBox) -> bool {
    let data = match box_data_ptr(data_ptr) {
        Some(ptr) => ptr,
        None => return true,
    };
    let rc = box_refcount_ptr(data);
    unsafe { (*rc).load(Ordering::Relaxed) == 1 }
}

fn box_data_ptr(data_ptr: RocBox) -> Option<*mut u8> {
    if data_ptr.is_null() {
        None
    } else {
        Some(data_ptr as *mut u8)
    }
}

fn box_refcount_ptr(data: *mut u8) -> *mut AtomicIsize {
    unsafe { data.sub(core::mem::size_of::<isize>()) as *mut AtomicIsize }
}

fn free_box_allocation(
    data: *mut u8,
    payload_alignment: usize,
    payload_contains_refcounted: bool,
    roc_host: &RocHost,
) {
    let ptr_width = core::mem::size_of::<usize>();
    let required_space = if payload_contains_refcounted { 2 * ptr_width } else { ptr_width };
    let header_bytes = required_space.max(payload_alignment);
    let alloc_alignment = ptr_width.max(payload_alignment);
    let base = unsafe { data.sub(header_bytes) } as *mut c_void;
    unsafe {
        roc_host.dealloc(base, alloc_alignment);
    }
}

/// A Roc string value. Small strings (up to 23 bytes on 64-bit) are stored inline;
/// larger strings are heap-allocated with a reference count.
///
/// `bytes` is never tagged. Operations, host code, glue code, and object-file
/// relocations can use it directly as the UTF-8 byte pointer for non-small
/// strings. Seamless-slice tagging lives in `capacity_or_alloc_ptr` instead.
/// Big-string capacity is stored shifted left by one bit, so max capacity is
/// essentially `isize::MAX` bytes: about 2 GiB on 32-bit targets and 8 EiB on
/// 64-bit targets.
///
/// This type is ABI-compatible with the Zig RocStr (24 bytes, `#[repr(C)]`).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct RocStr {
    pub bytes: *mut u8,
    pub capacity_or_alloc_ptr: usize,
    pub length: usize,
}

const ROC_STR_SIZE: usize = core::mem::size_of::<RocStr>();
const ROC_SMALL_STR_MAX_LEN: usize = ROC_STR_SIZE - 1;
const ROC_SMALL_STR_BIT: usize = isize::MIN as usize;
const ROC_SEAMLESS_SLICE_TAG: usize = 1;

impl RocStr {
    /// Return an empty RocStr (small string with zero length).
    pub fn empty() -> Self {
        Self {
            bytes: core::ptr::null_mut(),
            capacity_or_alloc_ptr: 0,
            length: ROC_SMALL_STR_BIT,
        }
    }

    /// Return true if this string is stored inline (small string optimization).
    #[inline]
    pub fn is_small_str(&self) -> bool {
        (self.length as isize) < 0
    }

    /// Return true if this string is a seamless slice into another allocation.
    #[inline]
    pub fn is_seamless_slice(&self) -> bool {
        !self.is_small_str() && (self.capacity_or_alloc_ptr & ROC_SEAMLESS_SLICE_TAG) != 0
    }

    /// Return the length of the string in bytes.
    #[inline]
    pub fn len(&self) -> usize {
        if self.is_small_str() {
            let bytes_ptr = self as *const Self as *const u8;
            let last_byte = unsafe { *bytes_ptr.add(ROC_STR_SIZE - 1) };
            (last_byte ^ 0b1000_0000) as usize
        } else {
            self.length
        }
    }

    /// Return true if the string has zero length.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Return the string contents as a byte slice.
    pub fn as_slice(&self) -> &[u8] {
        let ptr = self.as_u8_ptr();
        unsafe { core::slice::from_raw_parts(ptr, self.len()) }
    }

    /// Return a pointer to the raw UTF-8 bytes.
    #[inline]
    pub fn as_u8_ptr(&self) -> *const u8 {
        if self.is_small_str() {
            self as *const Self as *const u8
        } else {
            self.bytes as *const u8
        }
    }

    /// Return the string contents as a `&str`, assuming valid UTF-8.
    pub fn as_str(&self) -> &str {
        // SAFETY: Roc guarantees all strings are valid UTF-8.
        unsafe { core::str::from_utf8_unchecked(self.as_slice()) }
    }

    /// Create a RocStr from a byte slice, using `roc_host` for heap allocation if needed.
    pub fn from_slice(slice: &[u8], roc_host: &RocHost) -> Self {
        if slice.len() < ROC_STR_SIZE {
            let mut result = Self::empty();
            let ptr = &mut result as *mut Self as *mut u8;
            unsafe {
                core::ptr::copy_nonoverlapping(slice.as_ptr(), ptr, slice.len());
                *ptr.add(ROC_STR_SIZE - 1) = (slice.len() as u8) | 0b1000_0000;
            }
            result
        } else {
            let ptr_width = core::mem::size_of::<usize>();
            let total = ptr_width + slice.len();
            let base = unsafe { roc_host.alloc(core::mem::align_of::<usize>(), total) };
            let data_ptr = unsafe { (base as *mut u8).add(ptr_width) };
            // Write refcount = 1
            unsafe {
                let rc = (data_ptr as *mut isize).sub(1);
                *rc = 1;
                core::ptr::copy_nonoverlapping(slice.as_ptr(), data_ptr, slice.len());
            }
            Self {
                bytes: data_ptr,
                capacity_or_alloc_ptr: slice.len() << 1,
                length: slice.len(),
            }
        }
    }

    /// Create a RocStr from a `&str`.
    pub fn from_str(s: &str, roc_host: &RocHost) -> Self {
        Self::from_slice(s.as_bytes(), roc_host)
    }

    /// Decrement the reference count; frees the allocation when it reaches zero.
    pub fn decref(&self, roc_host: &RocHost) {
        if self.is_small_str() {
            return;
        }
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return;
        }
        unsafe {
            let rc = (alloc_ptr as *mut AtomicIsize).sub(1);
            if (*rc).load(Ordering::Relaxed) == 0 {
                return; // REFCOUNT_STATIC_DATA, bytes are in read-only memory
            }
            let prev = (*rc).fetch_sub(1, Ordering::Relaxed);
            if prev == 1 {
                let ptr_width = core::mem::size_of::<usize>();
                let base = alloc_ptr.sub(ptr_width) as *mut c_void;
                roc_host.dealloc(base, core::mem::align_of::<usize>());
            }
        }
    }

    /// Increment the reference count by `amount`.
    pub fn incref(&self, amount: isize) {
        if self.is_small_str() {
            return;
        }
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return;
        }
        unsafe {
            let rc = (alloc_ptr as *mut AtomicIsize).sub(1);
            if (*rc).load(Ordering::Relaxed) == 0 {
                return; // REFCOUNT_STATIC_DATA
            }
            (*rc).fetch_add(amount, Ordering::Relaxed);
        }
    }

    /// Return true if this string has a reference count of exactly one.
    pub fn is_unique(&self) -> bool {
        if self.is_small_str() {
            return true;
        }
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return true;
        }
        unsafe {
            let rc = (alloc_ptr as *const AtomicIsize).sub(1);
            let count = (*rc).load(Ordering::Relaxed);
            count == 0 || count == 1
        }
    }

    fn get_allocation_ptr(&self) -> *mut u8 {
        if self.is_seamless_slice() {
            (self.capacity_or_alloc_ptr & !ROC_SEAMLESS_SLICE_TAG) as *mut u8
        } else {
            self.bytes
        }
    }
}

impl core::fmt::Debug for RocStr {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("RocStr")
            .field("value", &self.as_str())
            .field("len", &self.len())
            .field("is_small", &self.is_small_str())
            .finish()
    }
}

/// A generic Roc list. Elements are reference-counted and heap-allocated.
///
/// When `ELEMENTS_REFCOUNTED` is true (the default via `RocList<T>`), an extra
/// `ptr_width` bytes are reserved in the allocation header for the element count,
/// matching the Roc runtime's `allocateWithRefcount` layout.
pub type RocList<T> = RocListWith<T, true>;

/// Parameterized list constructor; use `RocList<T>` for refcounted elements.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct RocListWith<T, const ELEMENTS_REFCOUNTED: bool> {
    pub elements: *mut T,
    pub length: usize,
    pub capacity_or_alloc_ptr: usize,
}

impl<T, const ELEMENTS_REFCOUNTED: bool> RocListWith<T, ELEMENTS_REFCOUNTED> {
    #[inline]
    fn header_bytes() -> usize {
        let ptr_width = core::mem::size_of::<usize>();
        let required_space = if ELEMENTS_REFCOUNTED { 2 * ptr_width } else { ptr_width };
        required_space.max(core::mem::align_of::<T>())
    }

    /// Return an empty RocList.
    pub fn empty() -> Self {
        Self {
            elements: core::ptr::null_mut(),
            length: 0,
            capacity_or_alloc_ptr: 0,
        }
    }

    /// Return the number of elements in the list.
    #[inline]
    pub fn len(&self) -> usize {
        self.length
    }

    /// Return true if the list has zero elements.
    #[inline]
    pub fn is_empty(&self) -> bool {
        self.length == 0
    }

    /// Return true if this list is a seamless slice into another allocation.
    /// Slices share the rc slot with their backing allocation; the alloc ptr is
    /// encoded in `capacity_or_alloc_ptr` with the low bit set.
    #[inline]
    pub fn is_seamless_slice(&self) -> bool {
        (self.capacity_or_alloc_ptr & 1) != 0
    }

    /// Resolve `self` to the start of its backing allocation (the element block
    /// just after the rc slot). Returns `null` for empty lists. Handles both
    /// whole-backing and seamless-slice forms.
    fn get_allocation_ptr(&self) -> *mut u8 {
        if self.is_seamless_slice() {
            (self.capacity_or_alloc_ptr & !1) as *mut u8
        } else {
            self.elements as *mut u8
        }
    }

    fn allocation_element_count(&self) -> usize {
        if self.is_seamless_slice() && ELEMENTS_REFCOUNTED {
            let alloc_ptr = self.get_allocation_ptr();
            if alloc_ptr.is_null() {
                return 0;
            }
            unsafe {
                let ptr = alloc_ptr as *const usize;
                *ptr.sub(2)
            }
        } else {
            self.length
        }
    }

    /// Return the list elements as a slice.
    pub fn as_slice(&self) -> &[T] {
        if self.elements.is_null() {
            &[]
        } else {
            unsafe { core::slice::from_raw_parts(self.elements, self.length) }
        }
    }

    /// Return all items in the backing allocation, not just this slice.
    pub fn allocation_items(&self) -> &[T] {
        if self.elements.is_null() {
            &[]
        } else {
            unsafe { core::slice::from_raw_parts(self.get_allocation_ptr() as *const T, self.allocation_element_count()) }
        }
    }

    /// Allocate a new list with space for `length` elements.
    pub fn allocate(length: usize, roc_host: &RocHost) -> Self {
        if length == 0 {
            return Self::empty();
        }
        let align = core::mem::align_of::<T>().max(core::mem::align_of::<usize>());
        let header_bytes = Self::header_bytes();
        let data_bytes = length * core::mem::size_of::<T>();
        let total = data_bytes + header_bytes;
        let base = unsafe { roc_host.alloc(align, total) };
        let data_ptr = unsafe { (base as *mut u8).add(header_bytes) };
        // Write refcount = 1
        unsafe {
            let rc = (data_ptr as *mut isize).sub(1);
            *rc = 1;
        }
        Self {
            elements: data_ptr as *mut T,
            length,
            capacity_or_alloc_ptr: length << 1,
        }
    }

    /// Create a RocList from a slice, copying elements into a new allocation.
    pub fn from_slice(slice: &[T], roc_host: &RocHost) -> Self where T: Copy {
        if slice.is_empty() {
            return Self::empty();
        }
        let list = Self::allocate(slice.len(), roc_host);
        unsafe {
            core::ptr::copy_nonoverlapping(
                slice.as_ptr(),
                list.elements,
                slice.len(),
            );
        }
        list
    }

    /// Decrement the reference count; frees the allocation when it reaches zero.
    pub fn decref(&self, roc_host: &RocHost) {
        if self.elements.is_null() {
            return;
        }
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return;
        }
        let align = core::mem::align_of::<T>().max(core::mem::align_of::<usize>());
        let header_bytes = Self::header_bytes();
        unsafe {
            let rc = (alloc_ptr as *mut AtomicIsize).sub(1);
            if (*rc).load(Ordering::Relaxed) == 0 {
                return; // REFCOUNT_STATIC_DATA, elements are in read-only memory
            }
            let prev = (*rc).fetch_sub(1, Ordering::Relaxed);
            if prev == 1 {
                let base = alloc_ptr.sub(header_bytes) as *mut c_void;
                roc_host.dealloc(base, align);
            }
        }
    }

    /// Increment the reference count by `amount`.
    pub fn incref(&self, amount: isize) {
        if self.elements.is_null() {
            return;
        }
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return;
        }
        unsafe {
            let rc = (alloc_ptr as *mut AtomicIsize).sub(1);
            if (*rc).load(Ordering::Relaxed) == 0 {
                return; // REFCOUNT_STATIC_DATA
            }
            (*rc).fetch_add(amount, Ordering::Relaxed);
        }
    }

    /// Return true if this list has a reference count of exactly one.
    pub fn is_unique(&self) -> bool {
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return true;
        }
        unsafe {
            let rc = (alloc_ptr as *const AtomicIsize).sub(1);
            let count = (*rc).load(Ordering::Relaxed);
            count == 0 || count == 1
        }
    }

    /// Return true if this list's allocation has exactly one counted ref.
    pub fn has_one_ref(&self) -> bool {
        let alloc_ptr = self.get_allocation_ptr();
        if alloc_ptr.is_null() {
            return false;
        }
        unsafe {
            let rc = (alloc_ptr as *const AtomicIsize).sub(1);
            (*rc).load(Ordering::Relaxed) == 1
        }
    }
}

impl<T: core::fmt::Debug, const ELEMENTS_REFCOUNTED: bool> core::fmt::Debug for RocListWith<T, ELEMENTS_REFCOUNTED> {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_list().entries(self.as_slice().iter()).finish()
    }
}

/// Element type for __AnonStruct5
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct5 {
    pub init_bang: *mut c_void,
    pub render: *mut c_void,
    pub subscriptions: *mut c_void,
    pub update_bang: *mut c_void,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct5>() == 32, "AnonStruct5 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct5>() == 8, "AnonStruct5 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct5>() == 16, "AnonStruct5 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct5>() == 4, "AnonStruct5 alignment mismatch");

/// Element type for __AnonStruct10
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct10 {
    pub on_tick: RocErasedCallable,
    pub ms: u32,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct10>() == 16, "AnonStruct10 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct10>() == 8, "AnonStruct10 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct10>() == 8, "AnonStruct10 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct10>() == 4, "AnonStruct10 alignment mismatch");

/// Element type for __AnonStruct17
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct17 {
    pub event: RocStr,
    pub keys: RocList<RocStr>,
    pub on_key: RocErasedCallable,
    pub prevent_default: bool,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct17>() == 64, "AnonStruct17 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct17>() == 8, "AnonStruct17 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct17>() == 32, "AnonStruct17 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct17>() == 4, "AnonStruct17 alignment mismatch");

/// Element type for __AnonStruct22
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct22 {
    pub code: RocStr,
    pub key: RocStr,
    pub alt: bool,
    pub ctrl: bool,
    pub is_composing: bool,
    pub meta: bool,
    pub repeat: bool,
    pub shift: bool,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct22>() == 56, "AnonStruct22 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct22>() == 8, "AnonStruct22 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct22>() == 32, "AnonStruct22 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct22>() == 4, "AnonStruct22 alignment mismatch");

/// Element type for __AnonStruct25
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct25 {
    pub name: RocStr,
    pub on_value: RocErasedCallable,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct25>() == 32, "AnonStruct25 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct25>() == 8, "AnonStruct25 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct25>() == 16, "AnonStruct25 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct25>() == 4, "AnonStruct25 alignment mismatch");

/// Element type for __AnonStruct29
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct29 {
    pub on_change: RocErasedCallable,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct29>() == 8, "AnonStruct29 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct29>() == 8, "AnonStruct29 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct29>() == 4, "AnonStruct29 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct29>() == 4, "AnonStruct29 alignment mismatch");

/// Element type for __AnonStruct34
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct34 {
    pub _1: RocList<CmdType36>,
    pub _0: *mut c_void,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct34>() == 32, "AnonStruct34 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct34>() == 8, "AnonStruct34 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct34>() == 16, "AnonStruct34 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct34>() == 4, "AnonStruct34 alignment mismatch");

/// Element type for __AnonStruct38
/// The header record `{ name : Str, value : Str }` (fields in ascending
/// name order, which is also their source order).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct38 {
    pub name: RocStr,
    pub value: RocStr,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct38>() == 48, "AnonStruct38 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct38>() == 8, "AnonStruct38 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct38>() == 24, "AnonStruct38 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct38>() == 4, "AnonStruct38 alignment mismatch");

/// Element type for __AnonStruct43
/// The HTTP callback's argument record: the two lists are pointer-class and
/// tie-break by ascending name (body before headers), the U16 status trails.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct43 {
    pub body: RocListWith<u8, false>,
    pub headers: RocList<AnonStruct38>,
    pub status: u16,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct43>() == 56, "AnonStruct43 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct43>() == 8, "AnonStruct43 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct43>() == 28, "AnonStruct43 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct43>() == 4, "AnonStruct43 alignment mismatch");

/// Element type for __AnonStruct74
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct74 {
    pub _0: RocBox,
    pub _1: RocList<CmdType36>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct74>() == 32, "AnonStruct74 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct74>() == 8, "AnonStruct74 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct74>() == 16, "AnonStruct74 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct74>() == 4, "AnonStruct74 alignment mismatch");

/// Element type for __AnonStruct124
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct124 {
    pub on_tick: RocErasedCallable,
    pub ms: u32,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct124>() == 16, "AnonStruct124 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct124>() == 8, "AnonStruct124 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct124>() == 8, "AnonStruct124 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct124>() == 4, "AnonStruct124 alignment mismatch");

/// Element type for __AnonStruct128
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct128 {
    pub event: RocStr,
    pub keys: RocList<RocStr>,
    pub on_key: RocErasedCallable,
    pub prevent_default: bool,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct128>() == 64, "AnonStruct128 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct128>() == 8, "AnonStruct128 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct128>() == 32, "AnonStruct128 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct128>() == 4, "AnonStruct128 alignment mismatch");

/// Element type for __AnonStruct132
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct132 {
    pub name: RocStr,
    pub on_value: RocErasedCallable,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct132>() == 32, "AnonStruct132 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct132>() == 8, "AnonStruct132 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct132>() == 16, "AnonStruct132 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct132>() == 4, "AnonStruct132 alignment mismatch");

/// Element type for __AnonStruct136
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct136 {
    pub on_change: RocErasedCallable,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct136>() == 8, "AnonStruct136 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct136>() == 8, "AnonStruct136 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct136>() == 4, "AnonStruct136 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct136>() == 4, "AnonStruct136 alignment mismatch");

/// Element type for __AnonStruct151
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AnonStruct151 {
    pub code: RocStr,
    pub key: RocStr,
    pub alt: bool,
    pub ctrl: bool,
    pub is_composing: bool,
    pub meta: bool,
    pub repeat: bool,
    pub shift: bool,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AnonStruct151>() == 56, "AnonStruct151 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AnonStruct151>() == 8, "AnonStruct151 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AnonStruct151>() == 32, "AnonStruct151 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AnonStruct151>() == 4, "AnonStruct151 alignment mismatch");

/// The pointer callbacks' argument record (the platform's
/// `Attribute.PointerEvent`): six F64 coordinates then six byte-wide fields,
/// each group in ascending field-name order. Built per pointer dispatch by
/// the host.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct PointerArgs {
    pub client_x: f64,
    pub client_y: f64,
    pub offset_x: f64,
    pub offset_y: f64,
    pub page_x: f64,
    pub page_y: f64,
    pub alt: bool,
    pub button: u8,
    pub buttons: u8,
    pub ctrl: bool,
    pub meta: bool,
    pub shift: bool,
}

const _: () = assert!(core::mem::size_of::<PointerArgs>() == 56, "PointerArgs size mismatch");
const _: () = assert!(core::mem::align_of::<PointerArgs>() == 8, "PointerArgs alignment mismatch");

/// The file callbacks' argument record (the platform's `Attribute.FileInfo`):
/// the U64 size leads, then the two strings (mime, name), then the U32 id.
/// Built per file dispatch by the host.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct FileArgs {
    pub size: u64,
    pub mime: RocStr,
    pub name: RocStr,
    pub id: u32,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<FileArgs>() == 64, "FileArgs size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<FileArgs>() == 40, "FileArgs size mismatch");
const _: () = assert!(core::mem::align_of::<FileArgs>() == 8, "FileArgs alignment mismatch");

/// Tag discriminant for Sub.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubType9Tag {
    Every = 0,
    Keyboard = 1,
    PortListen = 2,
    UrlChanged = 3,
}

/// Tag union: Sub
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SubType9 {
    pub payload: SubType9Payload,
    pub tag: SubType9Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union SubType9Payload {
    pub every: core::mem::ManuallyDrop<AnonStruct10>,
    pub keyboard: core::mem::ManuallyDrop<AnonStruct17>,
    pub port_listen: core::mem::ManuallyDrop<AnonStruct25>,
    pub url_changed: core::mem::ManuallyDrop<AnonStruct29>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<SubType9>() == 72, "SubType9 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<SubType9>() == 8, "SubType9 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<SubType9>() == 36, "SubType9 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<SubType9>() == 4, "SubType9 alignment mismatch");

/// Payload struct for CloseModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36CloseModalPayload {
    pub _0: RocStr,
}

/// Payload struct for ConsoleLog variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36ConsoleLogPayload {
    pub _0: RocStr,
}

/// Payload struct for CryptoDigest variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36CryptoDigestPayload {
    pub _0: RocStr,
    pub _1: RocListWith<u8, false>,
    pub _2: RocErasedCallable,
}

/// Payload struct for CryptoDigestFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36CryptoDigestFilePayload {
    pub _2: u64,
    pub _3: u64,
    pub _0: RocStr,
    pub _4: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for HttpSend variant.
/// Fields in layout order (sort key desc, name asc): the U64 timeout leads.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36HttpSendPayload {
    pub _4: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _3: RocListWith<u8, false>,
    pub _5: RocErasedCallable,
}

/// Payload struct for HttpSendFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36HttpSendFilePayload {
    pub _4: u64,
    pub _5: u64,
    pub _6: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _7: RocErasedCallable,
    pub _3: u32,
}

/// Payload struct for Navigate variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36NavigatePayload {
    pub _0: RocStr,
}

/// Payload struct for PortSend variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36PortSendPayload {
    pub _0: RocStr,
    pub _1: RocStr,
}

/// Payload struct for PushUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36PushUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ReplaceUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36ReplaceUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ShowModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36ShowModalPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeAfter variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36TimeAfterPayload {
    pub _0: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for TimeCancel variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36TimeCancelPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeDebounce variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36TimeDebouncePayload {
    pub _0: RocStr,
    pub _2: RocErasedCallable,
    pub _1: u32,
}

/// Tag discriminant for Cmd.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmdType36Tag {
    CloseModal = 0,
    ConsoleLog = 1,
    CryptoDigest = 2,
    CryptoDigestFile = 3,
    HttpSend = 4,
    HttpSendFile = 5,
    Navigate = 6,
    PortSend = 7,
    PushUrl = 8,
    ReplaceUrl = 9,
    ShowModal = 10,
    TimeAfter = 11,
    TimeCancel = 12,
    TimeDebounce = 13,
}

/// Tag union: Cmd
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType36 {
    pub payload: CmdType36Payload,
    pub tag: CmdType36Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union CmdType36Payload {
    pub close_modal: core::mem::ManuallyDrop<CmdType36CloseModalPayload>,
    pub console_log: core::mem::ManuallyDrop<CmdType36ConsoleLogPayload>,
    pub crypto_digest: core::mem::ManuallyDrop<CmdType36CryptoDigestPayload>,
    pub crypto_digest_file: core::mem::ManuallyDrop<CmdType36CryptoDigestFilePayload>,
    pub http_send: core::mem::ManuallyDrop<CmdType36HttpSendPayload>,
    pub http_send_file: core::mem::ManuallyDrop<CmdType36HttpSendFilePayload>,
    pub navigate: core::mem::ManuallyDrop<CmdType36NavigatePayload>,
    pub port_send: core::mem::ManuallyDrop<CmdType36PortSendPayload>,
    pub push_url: core::mem::ManuallyDrop<CmdType36PushUrlPayload>,
    pub replace_url: core::mem::ManuallyDrop<CmdType36ReplaceUrlPayload>,
    pub show_modal: core::mem::ManuallyDrop<CmdType36ShowModalPayload>,
    pub time_after: core::mem::ManuallyDrop<CmdType36TimeAfterPayload>,
    pub time_cancel: core::mem::ManuallyDrop<CmdType36TimeCancelPayload>,
    pub time_debounce: core::mem::ManuallyDrop<CmdType36TimeDebouncePayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<CmdType36>() == 120, "CmdType36 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<CmdType36>() == 8, "CmdType36 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<CmdType36>() == 80, "CmdType36 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<CmdType36>() == 8, "CmdType36 alignment mismatch");

/// Payload struct for Element variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType50ElementPayload {
    pub _0: RocStr,
    pub _1: RocList<AttributeType52>,
    pub _2: RocList<HtmlType62>,
}

/// Tag discriminant for Html.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HtmlType50Tag {
    Element = 0,
    Lazy = 1,
    Text = 2,
}

/// Tag union: Html
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType50 {
    pub payload: HtmlType50Payload,
    pub tag: HtmlType50Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union HtmlType50Payload {
    pub element: core::mem::ManuallyDrop<HtmlType50ElementPayload>,
    pub lazy: RocErasedCallable,
    pub text: core::mem::ManuallyDrop<RocStr>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<HtmlType50>() == 80, "HtmlType50 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<HtmlType50>() == 8, "HtmlType50 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<HtmlType50>() == 40, "HtmlType50 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<HtmlType50>() == 4, "HtmlType50 alignment mismatch");

/// Payload struct for Boolean variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52BooleanPayload {
    pub _0: RocStr,
    pub _1: bool,
}

/// Payload struct for KeyHandler variant.
/// Roc: KeyHandler(name, keys, prevent_default, stop_propagation, cb);
/// the layout sorts the callable ahead of the two bools, which keep their
/// source order after it.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52KeyHandlerPayload {
    pub _0: RocStr,
    pub _1: RocList<RocStr>,
    pub _2: RocErasedCallable,
    pub _3: bool,
    pub _4: bool,
}

/// Payload struct for MsgHandler variant.
/// Roc: MsgHandler(name, prevent_default, stop_propagation, msg).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52MsgHandlerPayload {
    pub _0: RocStr,
    pub _1: RocBox,
    pub _2: bool,
    pub _3: bool,
}

/// Payload struct for PointerHandler variant.
/// Roc: PointerHandler(name, prevent_default, stop_propagation, cb).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52PointerHandlerPayload {
    pub _0: RocStr,
    pub _1: RocErasedCallable,
    pub _2: bool,
    pub _3: bool,
}

/// Payload struct for PropertyHandler variant.
/// Roc: PropertyHandler(name, property, prevent_default, stop_propagation, cb).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52PropertyHandlerPayload {
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocErasedCallable,
    pub _3: bool,
    pub _4: bool,
}

/// Payload struct for String variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52StringPayload {
    pub _0: RocStr,
    pub _1: RocStr,
}

/// Payload struct for VisibilityHandler variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52VisibilityHandlerPayload {
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocBox,
}

/// Tag discriminant for Attribute.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AttributeType52Tag {
    Boolean = 0,
    FileHandler = 1,
    Key = 2,
    KeyHandler = 3,
    MsgHandler = 4,
    PointerHandler = 5,
    PropertyHandler = 6,
    String = 7,
    VisibilityHandler = 8,
}

/// Tag union: Attribute
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType52 {
    pub payload: AttributeType52Payload,
    pub tag: AttributeType52Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union AttributeType52Payload {
    pub boolean: core::mem::ManuallyDrop<AttributeType52BooleanPayload>,
    pub file_handler: core::mem::ManuallyDrop<RocErasedCallable>,
    pub key: core::mem::ManuallyDrop<RocStr>,
    pub key_handler: core::mem::ManuallyDrop<AttributeType52KeyHandlerPayload>,
    pub msg_handler: core::mem::ManuallyDrop<AttributeType52MsgHandlerPayload>,
    pub pointer_handler: core::mem::ManuallyDrop<AttributeType52PointerHandlerPayload>,
    pub property_handler: core::mem::ManuallyDrop<AttributeType52PropertyHandlerPayload>,
    pub string: core::mem::ManuallyDrop<AttributeType52StringPayload>,
    pub visibility_handler: core::mem::ManuallyDrop<AttributeType52VisibilityHandlerPayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AttributeType52>() == 72, "AttributeType52 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AttributeType52>() == 8, "AttributeType52 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AttributeType52>() == 36, "AttributeType52 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AttributeType52>() == 4, "AttributeType52 alignment mismatch");

/// Payload struct for Element variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType62ElementPayload {
    pub _0: RocStr,
    pub _1: RocList<AttributeType52>,
    pub _2: RocList<HtmlType62>,
}

/// Tag discriminant for Html.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HtmlType62Tag {
    Element = 0,
    Lazy = 1,
    Text = 2,
}

/// Tag union: Html
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType62 {
    pub payload: HtmlType62Payload,
    pub tag: HtmlType62Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union HtmlType62Payload {
    pub element: core::mem::ManuallyDrop<HtmlType62ElementPayload>,
    pub lazy: RocErasedCallable,
    pub text: core::mem::ManuallyDrop<RocStr>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<HtmlType62>() == 80, "HtmlType62 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<HtmlType62>() == 8, "HtmlType62 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<HtmlType62>() == 40, "HtmlType62 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<HtmlType62>() == 4, "HtmlType62 alignment mismatch");

/// Payload struct for None variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionType64NonePayload {
    pub _0: RocList<CmdType66>,
}

/// Payload struct for Update variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionType64UpdatePayload {
    pub _0: RocList<CmdType66>,
    pub _1: *mut c_void,
}

/// Tag discriminant for Action.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActionType64Tag {
    None = 0,
    Update = 1,
}

/// Tag union: Action
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionType64 {
    pub payload: ActionType64Payload,
    pub tag: ActionType64Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union ActionType64Payload {
    pub none: core::mem::ManuallyDrop<ActionType64NonePayload>,
    pub update: core::mem::ManuallyDrop<ActionType64UpdatePayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<ActionType64>() == 40, "ActionType64 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<ActionType64>() == 8, "ActionType64 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<ActionType64>() == 20, "ActionType64 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<ActionType64>() == 4, "ActionType64 alignment mismatch");

/// Payload struct for CloseModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66CloseModalPayload {
    pub _0: RocStr,
}

/// Payload struct for ConsoleLog variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66ConsoleLogPayload {
    pub _0: RocStr,
}

/// Payload struct for CryptoDigest variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66CryptoDigestPayload {
    pub _0: RocStr,
    pub _1: RocListWith<u8, false>,
    pub _2: RocErasedCallable,
}

/// Payload struct for CryptoDigestFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66CryptoDigestFilePayload {
    pub _2: u64,
    pub _3: u64,
    pub _0: RocStr,
    pub _4: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for HttpSend variant.
/// Fields in layout order (sort key desc, name asc): the U64 timeout leads.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66HttpSendPayload {
    pub _4: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _3: RocListWith<u8, false>,
    pub _5: RocErasedCallable,
}

/// Payload struct for HttpSendFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66HttpSendFilePayload {
    pub _4: u64,
    pub _5: u64,
    pub _6: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _7: RocErasedCallable,
    pub _3: u32,
}

/// Payload struct for Navigate variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66NavigatePayload {
    pub _0: RocStr,
}

/// Payload struct for PortSend variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66PortSendPayload {
    pub _0: RocStr,
    pub _1: RocStr,
}

/// Payload struct for PushUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66PushUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ReplaceUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66ReplaceUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ShowModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66ShowModalPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeAfter variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66TimeAfterPayload {
    pub _0: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for TimeCancel variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66TimeCancelPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeDebounce variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66TimeDebouncePayload {
    pub _0: RocStr,
    pub _2: RocErasedCallable,
    pub _1: u32,
}

/// Tag discriminant for Cmd.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmdType66Tag {
    CloseModal = 0,
    ConsoleLog = 1,
    CryptoDigest = 2,
    CryptoDigestFile = 3,
    HttpSend = 4,
    HttpSendFile = 5,
    Navigate = 6,
    PortSend = 7,
    PushUrl = 8,
    ReplaceUrl = 9,
    ShowModal = 10,
    TimeAfter = 11,
    TimeCancel = 12,
    TimeDebounce = 13,
}

/// Tag union: Cmd
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType66 {
    pub payload: CmdType66Payload,
    pub tag: CmdType66Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union CmdType66Payload {
    pub close_modal: core::mem::ManuallyDrop<CmdType66CloseModalPayload>,
    pub console_log: core::mem::ManuallyDrop<CmdType66ConsoleLogPayload>,
    pub crypto_digest: core::mem::ManuallyDrop<CmdType66CryptoDigestPayload>,
    pub crypto_digest_file: core::mem::ManuallyDrop<CmdType66CryptoDigestFilePayload>,
    pub http_send: core::mem::ManuallyDrop<CmdType66HttpSendPayload>,
    pub http_send_file: core::mem::ManuallyDrop<CmdType66HttpSendFilePayload>,
    pub navigate: core::mem::ManuallyDrop<CmdType66NavigatePayload>,
    pub port_send: core::mem::ManuallyDrop<CmdType66PortSendPayload>,
    pub push_url: core::mem::ManuallyDrop<CmdType66PushUrlPayload>,
    pub replace_url: core::mem::ManuallyDrop<CmdType66ReplaceUrlPayload>,
    pub show_modal: core::mem::ManuallyDrop<CmdType66ShowModalPayload>,
    pub time_after: core::mem::ManuallyDrop<CmdType66TimeAfterPayload>,
    pub time_cancel: core::mem::ManuallyDrop<CmdType66TimeCancelPayload>,
    pub time_debounce: core::mem::ManuallyDrop<CmdType66TimeDebouncePayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<CmdType66>() == 120, "CmdType66 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<CmdType66>() == 8, "CmdType66 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<CmdType66>() == 80, "CmdType66 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<CmdType66>() == 8, "CmdType66 alignment mismatch");

/// Payload struct for None variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionType81NonePayload {
    pub _0: RocList<CmdType84>,
}

/// Payload struct for Update variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionType81UpdatePayload {
    pub _0: RocBox,
    pub _1: RocList<CmdType84>,
}

/// Tag discriminant for Action.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActionType81Tag {
    None = 0,
    Update = 1,
}

/// Tag union: Action
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ActionType81 {
    pub payload: ActionType81Payload,
    pub tag: ActionType81Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union ActionType81Payload {
    pub none: core::mem::ManuallyDrop<ActionType81NonePayload>,
    pub update: core::mem::ManuallyDrop<ActionType81UpdatePayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<ActionType81>() == 40, "ActionType81 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<ActionType81>() == 8, "ActionType81 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<ActionType81>() == 20, "ActionType81 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<ActionType81>() == 4, "ActionType81 alignment mismatch");

/// Payload struct for CloseModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84CloseModalPayload {
    pub _0: RocStr,
}

/// Payload struct for ConsoleLog variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84ConsoleLogPayload {
    pub _0: RocStr,
}

/// Payload struct for CryptoDigest variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84CryptoDigestPayload {
    pub _0: RocStr,
    pub _1: RocListWith<u8, false>,
    pub _2: RocErasedCallable,
}

/// Payload struct for CryptoDigestFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84CryptoDigestFilePayload {
    pub _2: u64,
    pub _3: u64,
    pub _0: RocStr,
    pub _4: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for HttpSend variant.
/// Fields in layout order (sort key desc, name asc): the U64 timeout leads.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84HttpSendPayload {
    pub _4: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _3: RocListWith<u8, false>,
    pub _5: RocErasedCallable,
}

/// Payload struct for HttpSendFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84HttpSendFilePayload {
    pub _4: u64,
    pub _5: u64,
    pub _6: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _7: RocErasedCallable,
    pub _3: u32,
}

/// Payload struct for Navigate variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84NavigatePayload {
    pub _0: RocStr,
}

/// Payload struct for PortSend variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84PortSendPayload {
    pub _0: RocStr,
    pub _1: RocStr,
}

/// Payload struct for PushUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84PushUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ReplaceUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84ReplaceUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ShowModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84ShowModalPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeAfter variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84TimeAfterPayload {
    pub _0: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for TimeCancel variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84TimeCancelPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeDebounce variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84TimeDebouncePayload {
    pub _0: RocStr,
    pub _2: RocErasedCallable,
    pub _1: u32,
}

/// Tag discriminant for Cmd.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmdType84Tag {
    CloseModal = 0,
    ConsoleLog = 1,
    CryptoDigest = 2,
    CryptoDigestFile = 3,
    HttpSend = 4,
    HttpSendFile = 5,
    Navigate = 6,
    PortSend = 7,
    PushUrl = 8,
    ReplaceUrl = 9,
    ShowModal = 10,
    TimeAfter = 11,
    TimeCancel = 12,
    TimeDebounce = 13,
}

/// Tag union: Cmd
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType84 {
    pub payload: CmdType84Payload,
    pub tag: CmdType84Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union CmdType84Payload {
    pub close_modal: core::mem::ManuallyDrop<CmdType84CloseModalPayload>,
    pub console_log: core::mem::ManuallyDrop<CmdType84ConsoleLogPayload>,
    pub crypto_digest: core::mem::ManuallyDrop<CmdType84CryptoDigestPayload>,
    pub crypto_digest_file: core::mem::ManuallyDrop<CmdType84CryptoDigestFilePayload>,
    pub http_send: core::mem::ManuallyDrop<CmdType84HttpSendPayload>,
    pub http_send_file: core::mem::ManuallyDrop<CmdType84HttpSendFilePayload>,
    pub navigate: core::mem::ManuallyDrop<CmdType84NavigatePayload>,
    pub port_send: core::mem::ManuallyDrop<CmdType84PortSendPayload>,
    pub push_url: core::mem::ManuallyDrop<CmdType84PushUrlPayload>,
    pub replace_url: core::mem::ManuallyDrop<CmdType84ReplaceUrlPayload>,
    pub show_modal: core::mem::ManuallyDrop<CmdType84ShowModalPayload>,
    pub time_after: core::mem::ManuallyDrop<CmdType84TimeAfterPayload>,
    pub time_cancel: core::mem::ManuallyDrop<CmdType84TimeCancelPayload>,
    pub time_debounce: core::mem::ManuallyDrop<CmdType84TimeDebouncePayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<CmdType84>() == 120, "CmdType84 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<CmdType84>() == 8, "CmdType84 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<CmdType84>() == 80, "CmdType84 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<CmdType84>() == 8, "CmdType84 alignment mismatch");

/// Payload struct for Element variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType99ElementPayload {
    pub _0: RocStr,
    pub _1: RocList<AttributeType101>,
    pub _2: RocList<HtmlType111>,
}

/// Tag discriminant for Html.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HtmlType99Tag {
    Element = 0,
    Lazy = 1,
    Text = 2,
}

/// Tag union: Html
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType99 {
    pub payload: HtmlType99Payload,
    pub tag: HtmlType99Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union HtmlType99Payload {
    pub element: core::mem::ManuallyDrop<HtmlType99ElementPayload>,
    pub lazy: RocErasedCallable,
    pub text: core::mem::ManuallyDrop<RocStr>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<HtmlType99>() == 80, "HtmlType99 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<HtmlType99>() == 8, "HtmlType99 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<HtmlType99>() == 40, "HtmlType99 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<HtmlType99>() == 4, "HtmlType99 alignment mismatch");

/// Payload struct for Boolean variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101BooleanPayload {
    pub _0: RocStr,
    pub _1: bool,
}

/// Payload struct for KeyHandler variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101KeyHandlerPayload {
    pub _0: RocStr,
    pub _1: RocList<RocStr>,
    pub _2: RocErasedCallable,
    pub _3: bool,
    pub _4: bool,
}

/// Payload struct for MsgHandler variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101MsgHandlerPayload {
    pub _0: RocStr,
    pub _1: RocBox,
    pub _2: bool,
    pub _3: bool,
}

/// Payload struct for PointerHandler variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101PointerHandlerPayload {
    pub _0: RocStr,
    pub _1: RocErasedCallable,
    pub _2: bool,
    pub _3: bool,
}

/// Payload struct for PropertyHandler variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101PropertyHandlerPayload {
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocErasedCallable,
    pub _3: bool,
    pub _4: bool,
}

/// Payload struct for String variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101StringPayload {
    pub _0: RocStr,
    pub _1: RocStr,
}

/// Payload struct for VisibilityHandler variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101VisibilityHandlerPayload {
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocBox,
}

/// Tag discriminant for Attribute.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AttributeType101Tag {
    Boolean = 0,
    FileHandler = 1,
    Key = 2,
    KeyHandler = 3,
    MsgHandler = 4,
    PointerHandler = 5,
    PropertyHandler = 6,
    String = 7,
    VisibilityHandler = 8,
}

/// Tag union: Attribute
#[repr(C)]
#[derive(Clone, Copy)]
pub struct AttributeType101 {
    pub payload: AttributeType101Payload,
    pub tag: AttributeType101Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union AttributeType101Payload {
    pub boolean: core::mem::ManuallyDrop<AttributeType101BooleanPayload>,
    pub file_handler: core::mem::ManuallyDrop<RocErasedCallable>,
    pub key: core::mem::ManuallyDrop<RocStr>,
    pub key_handler: core::mem::ManuallyDrop<AttributeType101KeyHandlerPayload>,
    pub msg_handler: core::mem::ManuallyDrop<AttributeType101MsgHandlerPayload>,
    pub pointer_handler: core::mem::ManuallyDrop<AttributeType101PointerHandlerPayload>,
    pub property_handler: core::mem::ManuallyDrop<AttributeType101PropertyHandlerPayload>,
    pub string: core::mem::ManuallyDrop<AttributeType101StringPayload>,
    pub visibility_handler: core::mem::ManuallyDrop<AttributeType101VisibilityHandlerPayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<AttributeType101>() == 72, "AttributeType101 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<AttributeType101>() == 8, "AttributeType101 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<AttributeType101>() == 36, "AttributeType101 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<AttributeType101>() == 4, "AttributeType101 alignment mismatch");

/// Payload struct for Element variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType111ElementPayload {
    pub _0: RocStr,
    pub _1: RocList<AttributeType101>,
    pub _2: RocList<HtmlType111>,
}

/// Tag discriminant for Html.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HtmlType111Tag {
    Element = 0,
    Lazy = 1,
    Text = 2,
}

/// Tag union: Html
#[repr(C)]
#[derive(Clone, Copy)]
pub struct HtmlType111 {
    pub payload: HtmlType111Payload,
    pub tag: HtmlType111Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union HtmlType111Payload {
    pub element: core::mem::ManuallyDrop<HtmlType111ElementPayload>,
    pub lazy: RocErasedCallable,
    pub text: core::mem::ManuallyDrop<RocStr>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<HtmlType111>() == 80, "HtmlType111 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<HtmlType111>() == 8, "HtmlType111 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<HtmlType111>() == 40, "HtmlType111 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<HtmlType111>() == 4, "HtmlType111 alignment mismatch");

/// Payload struct for CloseModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114CloseModalPayload {
    pub _0: RocStr,
}

/// Payload struct for ConsoleLog variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114ConsoleLogPayload {
    pub _0: RocStr,
}

/// Payload struct for CryptoDigest variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114CryptoDigestPayload {
    pub _0: RocStr,
    pub _1: RocListWith<u8, false>,
    pub _2: RocErasedCallable,
}

/// Payload struct for CryptoDigestFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114CryptoDigestFilePayload {
    pub _2: u64,
    pub _3: u64,
    pub _0: RocStr,
    pub _4: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for HttpSend variant.
/// Fields in layout order (sort key desc, name asc): the U64 timeout leads.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114HttpSendPayload {
    pub _4: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _3: RocListWith<u8, false>,
    pub _5: RocErasedCallable,
}

/// Payload struct for HttpSendFile variant.
/// Fields in layout order (sort key desc, name asc): U64s, pointer-class, U32.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114HttpSendFilePayload {
    pub _4: u64,
    pub _5: u64,
    pub _6: u64,
    pub _0: RocStr,
    pub _1: RocStr,
    pub _2: RocList<AnonStruct38>,
    pub _7: RocErasedCallable,
    pub _3: u32,
}

/// Payload struct for Navigate variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114NavigatePayload {
    pub _0: RocStr,
}

/// Payload struct for PortSend variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114PortSendPayload {
    pub _0: RocStr,
    pub _1: RocStr,
}

/// Payload struct for PushUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114PushUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ReplaceUrl variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114ReplaceUrlPayload {
    pub _0: RocStr,
}

/// Payload struct for ShowModal variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114ShowModalPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeAfter variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114TimeAfterPayload {
    pub _0: RocErasedCallable,
    pub _1: u32,
}

/// Payload struct for TimeCancel variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114TimeCancelPayload {
    pub _0: RocStr,
}

/// Payload struct for TimeDebounce variant.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114TimeDebouncePayload {
    pub _0: RocStr,
    pub _2: RocErasedCallable,
    pub _1: u32,
}

/// Tag discriminant for Cmd.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CmdType114Tag {
    CloseModal = 0,
    ConsoleLog = 1,
    CryptoDigest = 2,
    CryptoDigestFile = 3,
    HttpSend = 4,
    HttpSendFile = 5,
    Navigate = 6,
    PortSend = 7,
    PushUrl = 8,
    ReplaceUrl = 9,
    ShowModal = 10,
    TimeAfter = 11,
    TimeCancel = 12,
    TimeDebounce = 13,
}

/// Tag union: Cmd
#[repr(C)]
#[derive(Clone, Copy)]
pub struct CmdType114 {
    pub payload: CmdType114Payload,
    pub tag: CmdType114Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union CmdType114Payload {
    pub close_modal: core::mem::ManuallyDrop<CmdType114CloseModalPayload>,
    pub console_log: core::mem::ManuallyDrop<CmdType114ConsoleLogPayload>,
    pub crypto_digest: core::mem::ManuallyDrop<CmdType114CryptoDigestPayload>,
    pub crypto_digest_file: core::mem::ManuallyDrop<CmdType114CryptoDigestFilePayload>,
    pub http_send: core::mem::ManuallyDrop<CmdType114HttpSendPayload>,
    pub http_send_file: core::mem::ManuallyDrop<CmdType114HttpSendFilePayload>,
    pub navigate: core::mem::ManuallyDrop<CmdType114NavigatePayload>,
    pub port_send: core::mem::ManuallyDrop<CmdType114PortSendPayload>,
    pub push_url: core::mem::ManuallyDrop<CmdType114PushUrlPayload>,
    pub replace_url: core::mem::ManuallyDrop<CmdType114ReplaceUrlPayload>,
    pub show_modal: core::mem::ManuallyDrop<CmdType114ShowModalPayload>,
    pub time_after: core::mem::ManuallyDrop<CmdType114TimeAfterPayload>,
    pub time_cancel: core::mem::ManuallyDrop<CmdType114TimeCancelPayload>,
    pub time_debounce: core::mem::ManuallyDrop<CmdType114TimeDebouncePayload>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<CmdType114>() == 120, "CmdType114 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<CmdType114>() == 8, "CmdType114 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<CmdType114>() == 80, "CmdType114 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<CmdType114>() == 8, "CmdType114 alignment mismatch");

/// Tag discriminant for Sub.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SubType123Tag {
    Every = 0,
    Keyboard = 1,
    PortListen = 2,
    UrlChanged = 3,
}

/// Tag union: Sub
#[repr(C)]
#[derive(Clone, Copy)]
pub struct SubType123 {
    pub payload: SubType123Payload,
    pub tag: SubType123Tag,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub union SubType123Payload {
    pub every: core::mem::ManuallyDrop<AnonStruct124>,
    pub keyboard: core::mem::ManuallyDrop<AnonStruct128>,
    pub port_listen: core::mem::ManuallyDrop<AnonStruct132>,
    pub url_changed: core::mem::ManuallyDrop<AnonStruct136>,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::size_of::<SubType123>() == 72, "SubType123 size mismatch");
#[cfg(target_pointer_width = "64")]
const _: () = assert!(core::mem::align_of::<SubType123>() == 8, "SubType123 alignment mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::size_of::<SubType123>() == 36, "SubType123 size mismatch");
#[cfg(target_pointer_width = "32")]
const _: () = assert!(core::mem::align_of::<SubType123>() == 4, "SubType123 alignment mismatch");

// =============================================================================
// Runtime Symbols
//
// The host defines these linker symbols. Compiled Roc code calls them directly.
// =============================================================================

#[allow(improper_ctypes)]
unsafe extern "C" {
    pub fn roc_alloc(length: usize, alignment: usize) -> *mut c_void;
    pub fn roc_dealloc(ptr: *mut c_void, alignment: usize);
    pub fn roc_realloc(ptr: *mut c_void, new_length: usize, alignment: usize) -> *mut c_void;
    pub fn roc_dbg(bytes: *const u8, len: usize);
    pub fn roc_expect_failed(bytes: *const u8, len: usize);
    pub fn roc_crashed(bytes: *const u8, len: usize);
}

// The platform declares no hosted functions: the app is pure and
// every observable effect crosses as Effect data through the provided entry
// points below.

// =============================================================================
// Provided Symbols
//
// Roc exports these symbols from the app with their natural C ABI signatures.
// =============================================================================

#[allow(improper_ctypes)]
unsafe extern "C" {
    /// Entrypoint: init_for_host
    pub fn roc_init(arg0: RocStr) -> AnonStruct74;

    /// Entrypoint: update_for_host
    pub fn roc_update(arg0: RocBox, arg1: RocBox) -> AnonStruct74;

    /// Entrypoint: render_for_host
    pub fn roc_render(arg0: RocBox) -> HtmlType50;

    /// Entrypoint: subs_for_host
    pub fn roc_subs(arg0: RocBox) -> RocList<SubType9>;

    /// Entrypoint: drop_model_for_host
    pub fn roc_drop_model(arg0: RocBox);

    /// Entrypoint: drop_view_for_host
    pub fn roc_drop_view(arg0: HtmlType99);

    /// Entrypoint: drop_effects_for_host (symbol name kept for ABI stability)
    pub fn roc_drop_cmds(arg0: RocList<CmdType114>);

    /// Entrypoint: drop_subs_for_host
    pub fn roc_drop_subs(arg0: RocList<SubType123>);

    /// Entrypoint: drop_http_callback_for_host
    pub fn roc_drop_http_callback(arg0: RocErasedCallable);

    /// Entrypoint: drop_timer_callback_for_host
    pub fn roc_drop_timer_callback(arg0: RocErasedCallable);

    /// Entrypoint: drop_key_callback_for_host
    pub fn roc_drop_key_callback(arg0: RocErasedCallable);

    /// Entrypoint: drop_value_callback_for_host
    pub fn roc_drop_value_callback(arg0: RocErasedCallable);

    pub fn roc_drop_pointer_callback(arg0: RocErasedCallable);

    pub fn roc_drop_file_callback(arg0: RocErasedCallable);

    pub fn roc_drop_bytes_callback(arg0: RocErasedCallable);

    /// Entrypoint: drop_str_for_host
    pub fn roc_drop_str(arg0: RocStr);

    /// Entrypoint: drop_bytes_for_host
    pub fn roc_drop_bytes(arg0: RocListWith<u8, false>);

}
