use std::{
    fs,
    path::{Path, PathBuf},
};

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_the_selected_game_path() {
        let dir = std::env::temp_dir().join(format!("mpm-pref-{}", std::process::id()));
        assert_eq!(saved_game(&dir), None);
        let game = PathBuf::from("D:/Steam/steamapps/common/Machine Party");
        save_game(&dir, &game).unwrap();
        assert_eq!(saved_game(&dir), Some(game));
        fs::remove_dir_all(dir).unwrap();
    }
}
