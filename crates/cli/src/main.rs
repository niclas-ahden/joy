use roc_std::RocRefcounted;

fn main() {
    let mut boxed_model = roc::roc_init();

    // stop roc from deallocating the model
    boxed_model.inc();

    let roc_html = roc::roc_render(boxed_model.clone());

    // EXPECT NOT CLICKED
    dbg!(roc_html);

    // Str.toUtf8 "UserClickedText"
    let event_bytes = [
        85, 115, 101, 114, 67, 108, 105, 99, 107, 101, 100, 84, 101, 120, 116,
    ];

    let mut action = roc::roc_update(boxed_model, &mut event_bytes.into());

    dbg!(&action);

    assert_eq!(action.discriminant(), roc::glue::DiscriminantAction::Update);

    let roc_html = roc::roc_render(action.unwrap_model());

    // EXPECT CLICKED
    dbg!(roc_html);
}
