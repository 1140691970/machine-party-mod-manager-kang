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

/// Returns the directory directly containing `Machine Party.exe` and `Machine Party.pck`.
pub fn resolve_pck_dir(dir: &Path) -> Option<PathBuf> {
    let copies = copy_directories(dir);
    (copies.len() == 1).then(|| copies[0].clone())
}

pub fn copy_directories(dir: &Path) -> Vec<PathBuf> {
    if game_files(dir) {
        return vec![dir.to_owned()];
    }
    let mut copies: Vec<_> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_dir()))
        .map(|entry| entry.path())
        .filter(|path| game_files(path))
        .collect();
    copies.sort();
    copies
}

/// A game copy may keep its files directly in the folder or in one version subfolder.
pub fn is_game_root(dir: &Path) -> bool {
    resolve_pck_dir(dir).is_some()
}

pub fn steam_installations() -> Vec<PathBuf> {
    let mut games = vec![];
    for steam in steamlocate::locate_all().unwrap_or_default() {
        for library in steam.libraries().into_iter().flatten().flatten() {
            if let Some(Ok(info)) = library.app(STEAM_APP_ID) {
                let path = library.resolve_app_dir(&info);
                let copies = copy_directories(&path);
                if copies.len() > 1 {
                    games.extend(copies);
                } else if copies.len() == 1 && !games.contains(&path) {
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

    #[test]
    fn resolves_pck_dir_for_root_and_nested_layout() {
        let root = std::env::temp_dir().join(format!("mpm-pck-dir-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let nested = root.join("Machine Party_Windows");
        fs::create_dir_all(&nested).unwrap();
        fs::write(nested.join("Machine Party.exe"), []).unwrap();
        assert_eq!(resolve_pck_dir(&root), None);
        fs::write(nested.join("Machine Party.pck"), []).unwrap();
        assert_eq!(resolve_pck_dir(&root), Some(nested.clone()));
        assert_eq!(resolve_pck_dir(&nested), Some(nested));
        let second = root.join("another version");
        fs::create_dir(&second).unwrap();
        for name in ["Machine Party.exe", "Machine Party.pck"] {
            fs::write(second.join(name), []).unwrap();
        }
        assert!(resolve_pck_dir(&root).is_none());
        assert_eq!(copy_directories(&root).len(), 2);
        fs::remove_dir_all(root).unwrap();
    }
}
