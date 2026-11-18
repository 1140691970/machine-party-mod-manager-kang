use std::{
    fs,
    path::{Path, PathBuf},
};

pub const STEAM_APP_ID: u32 = 4108000;

fn game_files(dir: &Path) -> bool {
    ["Machine Party.exe", "Machine Party.pck"]
        .iter()
        .all(|name| dir.join(name).is_file())
}

/// A game copy may keep its files directly in the folder or in one version subfolder.
pub fn is_game_root(dir: &Path) -> bool {
    game_files(dir)
        || fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .any(|entry| {
                entry.file_type().is_ok_and(|kind| kind.is_dir()) && game_files(&entry.path())
            })
}

pub fn steam_installations() -> Vec<PathBuf> {
    let mut games = vec![];
    for steam in steamlocate::locate_all().unwrap_or_default() {
        for library in steam.libraries().into_iter().flatten().flatten() {
            if let Some(Ok(info)) = library.app(STEAM_APP_ID) {
                let path = library.resolve_app_dir(&info);
                if is_game_root(&path) && !games.contains(&path) {
                    games.push(path);
                }
            }
        }
    }
    games
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_complete_copy_in_root_or_version_folder() {
        let root = std::env::temp_dir().join(format!("mpm-test-{}", std::process::id()));
        let child = root.join("v2.1.2");
        fs::create_dir_all(&child).unwrap();
        fs::write(child.join("Machine Party.exe"), []).unwrap();
        assert!(!is_game_root(&root));
        fs::write(child.join("Machine Party.pck"), []).unwrap();
        assert!(is_game_root(&root) && is_game_root(&child));
        fs::remove_dir_all(root).unwrap();
    }
}
