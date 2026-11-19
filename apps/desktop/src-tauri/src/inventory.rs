use std::{
    collections::BTreeMap,
    fs,
    io::{self, Write},
    path::{Path, PathBuf},
};

const INVENTORY_FILE: &str = "installations.json";

/// Installed versions keyed by `owner/repo` for one game copy.
pub type Installed = BTreeMap<String, String>;

// The installer records completed transactions per game copy. Missing records
// mean that this manager has not installed any mods for the selected copy.
type Inventory = BTreeMap<PathBuf, Installed>;

fn read_inventory(config_dir: &Path) -> Result<(Inventory, bool), String> {
    let bytes = match fs::read(config_dir.join(INVENTORY_FILE)) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {
            return Ok((Inventory::new(), false));
        }
        Err(_) => return Err("inventoryError".into()),
    };
    let inventory: Inventory = serde_json::from_slice(&bytes).map_err(|_| "inventoryError")?;
    Ok((inventory, true))
}

fn write_inventory(config_dir: &Path, inventory: &Inventory) -> Result<(), String> {
    fs::create_dir_all(config_dir).map_err(|_| "inventoryError")?;
    let bytes = serde_json::to_vec_pretty(inventory).map_err(|_| "inventoryError")?;
    let temp = config_dir.join(format!("{INVENTORY_FILE}.tmp-{}", std::process::id()));
    let mut file = fs::File::create(&temp).map_err(|_| "inventoryError")?;
    if file.write_all(&bytes).is_err() || file.sync_all().is_err() {
        let _ = fs::remove_file(&temp);
        return Err("inventoryError".into());
    }
    drop(file);
    fs::rename(&temp, config_dir.join(INVENTORY_FILE)).map_err(|_| {
        let _ = fs::remove_file(&temp);
        "inventoryError".into()
    })
}

pub fn installed_versions(config_dir: &Path, game: &Path) -> Result<Installed, String> {
    let (mut inventory, _) = read_inventory(config_dir)?;
    Ok(inventory.remove(game).unwrap_or_default())
}

pub fn record_installed(
    config_dir: &Path,
    game: &Path,
    repo: &str,
    version: &str,
) -> Result<(), String> {
    let (mut inventory, _) = read_inventory(config_dir)?;
    inventory
        .entry(game.to_path_buf())
        .or_default()
        .insert(repo.to_owned(), version.to_owned());
    write_inventory(config_dir, &inventory)
}

pub fn remove_installed(config_dir: &Path, game: &Path, repo: &str) -> Result<(), String> {
    let (mut inventory, existed) = read_inventory(config_dir)?;
    let Some(mods) = inventory.get_mut(game) else {
        return Ok(());
    };
    if mods.remove(repo).is_none() {
        return Ok(());
    }
    if mods.is_empty() {
        inventory.remove(game);
    }
    if existed {
        write_inventory(config_dir, &inventory)?;
    }
    Ok(())
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

    #[test]
    fn records_and_removes_versions_per_game_copy() {
        let dir = std::env::temp_dir().join(format!("mpm-inv-rw-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let game_a = Path::new("C:/Games/Machine Party");
        let game_b = Path::new("D:/Other/Machine Party");

        record_installed(&dir, game_a, "DarkJadeStone/MachineParty-Overtime", "v1.7").unwrap();
        record_installed(&dir, game_b, "Binary1936/machine-party-8p", "v1.5").unwrap();

        assert_eq!(
            installed_versions(&dir, game_a).unwrap()["DarkJadeStone/MachineParty-Overtime"],
            "v1.7"
        );
        assert_eq!(
            installed_versions(&dir, game_b).unwrap()["Binary1936/machine-party-8p"],
            "v1.5"
        );

        remove_installed(&dir, game_a, "DarkJadeStone/MachineParty-Overtime").unwrap();
        assert!(installed_versions(&dir, game_a).unwrap().is_empty());
        assert_eq!(
            installed_versions(&dir, game_b).unwrap()["Binary1936/machine-party-8p"],
            "v1.5"
        );

        let raw: serde_json::Value =
            serde_json::from_slice(&fs::read(dir.join(INVENTORY_FILE)).unwrap()).unwrap();
        assert!(raw.get("C:/Games/Machine Party").is_none());
        assert!(raw.get("D:/Other/Machine Party").is_some());

        fs::remove_dir_all(dir).unwrap();
    }
}
