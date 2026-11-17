fn main() {
    println!("cargo:rerun-if-env-changed=APP_DISPLAY_VERSION");
}
