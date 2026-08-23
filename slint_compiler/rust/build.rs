use std::env;

fn main() {
    let manifest_dir = env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR not set");
    let slint_path = format!("{}/../../example/todo.slint", manifest_dir);

    slint_build::compile(&slint_path)
        .expect("Failed to compile todo.slint — check the path and file syntax");

    println!("cargo:rerun-if-changed={}", slint_path);
}
