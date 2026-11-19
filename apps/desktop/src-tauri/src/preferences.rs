use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::game;

const GAME_PATH_FILE: &str = "game-path.json";

pub fn saved_game(config_dir: &Path) -> Option<PathBuf> {
    let contents = fs::read(config_dir.join(GAME_PATH_FILE)).ok()?;
    serde_json::from_slice(&contents).ok()
}

pub fn save_game(config_dir: &Path, game: &Path) -> Result<(), String> {
    fs::create_dir_all(config_dir).map_err(|e| e.to_string())?;
    let contents = serde_json::to_vec(game).map_err(|e| e.to_string())?;
    fs::write(config_dir.join(GAME_PATH_FILE), contents).map_err(|e| e.to_string())
}

/// Returns the cached valid game root when `!rescan`, or runs `detect` and caches a unique hit.
pub fn resolve_cached_or_detect(
    config_dir: &Path,
    rescan: bool,
    detect: impl FnOnce() -> Vec<PathBuf>,
) -> Vec<PathBuf> {
    let saved = saved_game(config_dir).filter(|path| game::is_game_root(path));
    if !rescan && let Some(path) = saved {
        return vec![path];
    }
    let games = detect();
    if games.len() == 1 {
        let _ = save_game(config_dir, &games[0]);
        return games;
    }
    if games.is_empty()
        && let Some(path) = saved
    {
        return vec![path];
    }
    games
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn make_game_copy(root: &Path) {
        let dir = root.join("Machine Party_Windows");
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("Machine Party.exe"), []).unwrap();
        fs::write(dir.join("Machine Party.pck"), []).unwrap();
    }

    #[test]
    fn round_trips_the_selected_game_path() {
        let dir = std::env::temp_dir().join(format!("mpm-pref-{}", std::process::id()));
        assert_eq!(saved_game(&dir), None);
        let game = PathBuf::from("D:/Steam/steamapps/common/Machine Party");
        save_game(&dir, &game).unwrap();
        assert_eq!(saved_game(&dir), Some(game));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn caches_single_detected_game_and_skips_rescan_until_requested() {
        let root = std::env::temp_dir().join(format!("mpm-pref-cache-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let config = root.join("cfg");
        let steam_game = root.join("steam").join("party project");
        let manual_game = root.join("manual").join("party project");
        make_game_copy(&steam_game);
        make_game_copy(&manual_game);

        let calls = Cell::new(0);
        let first = resolve_cached_or_detect(&config, false, || {
            calls.set(calls.get() + 1);
            vec![steam_game.clone()]
        });
        assert_eq!(first, vec![steam_game.clone()]);
        assert_eq!(calls.get(), 1);
        assert_eq!(saved_game(&config), Some(steam_game.clone()));

        let second = resolve_cached_or_detect(&config, false, || {
            calls.set(calls.get() + 1);
            vec![manual_game.clone()]
        });
        assert_eq!(second, vec![steam_game.clone()]);
        assert_eq!(calls.get(), 1);

        // Rescanning when Steam detection finds nothing preserves a valid manually chosen path.
        save_game(&config, &manual_game).unwrap();
        let preserved = resolve_cached_or_detect(&config, true, Vec::new);
        assert_eq!(preserved, vec![manual_game.clone()]);

        // An invalid/deleted saved path is discarded.
        fs::remove_dir_all(&manual_game).unwrap();
        let missing = resolve_cached_or_detect(&config, true, Vec::new);
        assert!(missing.is_empty());

        fs::remove_dir_all(root).unwrap();
    }
}
