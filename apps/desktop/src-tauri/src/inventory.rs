use std::{
    collections::BTreeMap,
    fs, io,
    path::{Path, PathBuf},
};

const INVENTORY_FILE: &str = "installations.json";

/// Installed versions keyed by `owner/repo` for one game copy.
pub type Installed = BTreeMap<String, String>;

// The installer records completed transactions per game copy. Missing records
// mean that this manager has not installed any mods for the selected copy.
type Inventory = BTreeMap<PathBuf, Installed>;

pub fn installed_versions(config_dir: &Path, game: &Path) -> Result<Installed, String> {
    let bytes = match fs::read(config_dir.join(INVENTORY_FILE)) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Installed::new()),
        Err(_) => return Err("inventoryError".into()),
    };
    let mut inventory: Inventory = serde_json::from_slice(&bytes).map_err(|_| "inventoryError")?;
    Ok(inventory.remove(game).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_records_for_the_selected_copy_only() {
        let dir = std::env::temp_dir().join(format!("mpm-inv-{}", std::process::id()));
        let game = Path::new("C:/Games/Machine Party");
        assert!(installed_versions(&dir, game).unwrap().is_empty());
        fs::create_dir_all(&dir).unwrap();
        fs::write(
            dir.join(INVENTORY_FILE),
            r#"{"C:/Games/Machine Party":{"DarkJadeStone/MachineParty-Overtime":"v1.6"},"D:/Other":{"a/b":"v1"}}"#,
        )
        .unwrap();
        let installed = installed_versions(&dir, game).unwrap();
        assert_eq!(installed.len(), 1);
        assert_eq!(installed["DarkJadeStone/MachineParty-Overtime"], "v1.6");
        fs::write(dir.join(INVENTORY_FILE), "not json").unwrap();
        assert_eq!(
            installed_versions(&dir, game).unwrap_err(),
            "inventoryError"
        );
        fs::remove_dir_all(dir).unwrap();
    }
}
