#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if std::env::args().any(|arg| arg == "--self-test") {
        if let Err(error) = hot_coffee_lib::self_test() {
            eprintln!("Hot Coffee self-test failed: {error}");
            std::process::exit(1);
        }
        return;
    }
    hot_coffee_lib::run();
}
