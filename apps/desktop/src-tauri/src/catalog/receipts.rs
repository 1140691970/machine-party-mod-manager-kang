// Keep the first signed description of an online-only mod for offline inspection
// and transaction-based uninstall, even after it disappears from the live catalog.
use serde::{Deserialize, Serialize};
use std::{fs, io::ErrorKind, path::Path};

#[derive(Deserialize, Serialize)]
struct Proof {
    document: String,
    signature: String,
}

pub(crate) fn save(config: &Path, id: &str, document: &str, signature: &str) -> Result<(), String> {
    let dir = config.join("mod-catalog-receipts");
    fs::create_dir_all(&dir).map_err(|_| "fileWriteError")?;
    let bytes =
        serde_json::to_vec(&serde_json::json!({ "document":document, "signature":signature }))
            .map_err(|_| "fileWriteError")?;
    crate::installer::write_atomic(&dir.join(format!("{id}.json")), &bytes)
}

pub(crate) fn load(config: &Path, key: &str) -> Result<Vec<serde_json::Value>, String> {
    let files = match fs::read_dir(config.join("mod-catalog-receipts")) {
        Ok(files) => files,
        Err(e) if e.kind() == ErrorKind::NotFound => return Ok(vec![]),
        Err(_) => return Err("fileReadError".into()),
    };
    let mut items = Vec::new();
    for file in files {
        let path = file.map_err(|_| "fileReadError")?.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        let Some(id) = path.file_stem().and_then(|id| id.to_str()) else {
            continue;
        };
        if super::entry(id).is_some() {
            continue;
        }
        let bytes = fs::read(path.as_path()).map_err(|_| "fileReadError")?;
        let Ok(proof) = serde_json::from_slice::<Proof>(&bytes) else {
            continue;
        };
        let Ok(approved) = super::signed_updates(&proof.document, &proof.signature, key, true)
        else {
            continue;
        };
        if approved.iter().any(|item| item.id == id) {
            let data: serde_json::Value =
                serde_json::from_str(&proof.document).map_err(|_| "catalogInvalid")?;
            if let Some(item) = data["mods"]
                .as_array()
                .and_then(|mods| mods.iter().find(|m| m["id"] == id))
            {
                items.push(item.clone());
            }
        }
    }
    Ok(items)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn restart_recovers_only_the_named_mod_from_an_authentic_catalog() {
        let fixture: serde_json::Value = serde_json::from_str(include_str!(
            "../../../../../tests/contracts/fixtures/native-catalog-proof.json"
        ))
        .unwrap();
        let key = fixture["key"].as_str().unwrap();
        let doc = fixture["document"].as_str().unwrap();
        let signature = fixture["signature"].as_str().unwrap();
        let dir = tempfile::tempdir().unwrap();
        let id = "fixture-online-hd";
        save(dir.path(), id, doc, signature).unwrap();
        save(dir.path(), "different-id", doc, signature).unwrap();
        let rows = load(dir.path(), key).unwrap();
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["id"], id);
        save(dir.path(), id, &format!("{doc} "), signature).unwrap();
        assert!(load(dir.path(), key).unwrap().is_empty());
    }
}
