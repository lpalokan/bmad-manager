use std::fs;
use std::path::Path;

fn main() {
    // `tauri.conf.json` registers `resources/node-portable/**/*`, etc.
    // under `bundle.resources`. In CI release builds those directories
    // are populated by the workflow before `pnpm tauri build` runs. For
    // every other invocation (local `cargo check`, the unit + BDD test
    // jobs in `tauri-windows-check.yml`, a `cargo build` on a dev mac)
    // the directories don't exist yet, and tauri-build rejects the glob
    // with "path not found or didn't match any files". Drop a marker
    // file into each directory so the globs always match at least one
    // entry. The .gitignore already excludes the directories from VCS,
    // and the markers are tiny — they're harmless if they end up in a
    // release bundle alongside the real binaries.
    for dir in [
        "resources/node-portable",
        "resources/portable-git",
        "resources/npm-cache",
    ] {
        let path = Path::new(dir);
        if let Err(err) = fs::create_dir_all(path) {
            println!("cargo:warning=could not create bundle placeholder {dir}: {err}");
            continue;
        }
        let marker = path.join(".placeholder");
        if !marker.exists() {
            if let Err(err) = fs::write(
                &marker,
                "Populated at build time by .github/workflows/tauri-windows.yml.\n",
            ) {
                println!(
                    "cargo:warning=could not write {} placeholder: {err}",
                    marker.display()
                );
            }
        }
    }

    tauri_build::build()
}
