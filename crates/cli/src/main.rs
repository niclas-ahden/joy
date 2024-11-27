fn main() {
    let mut boxed_model = roc::roc_init();

    let roc_html = roc::roc_render(&mut boxed_model);

    dbg!(&roc_html);

    println!("{}", roc_html);
}
