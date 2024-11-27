use std::cell::RefCell;

use roc_std::RocBox;

pub type Model = RocBox<()>;

thread_local! {
    static MODEL: RefCell<Option<Model>> = const { RefCell::new(None) };
}

pub fn with<T>(f: impl FnOnce(&mut Option<Model>) -> T) -> T {
    MODEL.with_borrow_mut(|model| f(model))
}
