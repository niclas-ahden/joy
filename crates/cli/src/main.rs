use roc_std::RocList;

fn main() {
    let first_model = roc::roc_init();

    let first_render = roc::roc_render(first_model.clone());

    dbg!(first_render);

    let mut action = roc::roc_update(
        first_model,
        // Str.toUtf8 "UserClickedText"
        &mut RocList::from([
            85, 115, 101, 114, 67, 108, 105, 99, 107, 101, 100, 84, 101, 120, 116,
        ]),
    );

    dbg!(&action);

    match action.discriminant() {
        roc::glue::DiscriminantAction::None => {
            // no action to take
        }
        roc::glue::DiscriminantAction::Update => {
            // we have a new model
            let new_model = action.unwrap_model();

            let second_html = roc::roc_render(new_model);

            dbg!(second_html);
        }
    }
}
