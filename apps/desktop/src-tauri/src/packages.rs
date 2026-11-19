use std::{
    fs,
    path::{Path, PathBuf},
};

use crate::{catalog::ModEntry, installer::file_fingerprint};

pub fn destination(config: &Path, item: &ModEntry) -> Result<PathBuf, String> {
    let pkg = item.package.as_ref().ok_or("missingPackage")?;
    Ok(config
        .join("packages")
        .join(&item.id)
        .join(&pkg.sha256)
        .join(&pkg.filename))
}

pub fn existing(config: &Path, item: &ModEntry) -> Result<PathBuf, String> {
    let pinned = destination(config, item)?;
    if pinned.try_exists().map_err(|_| "fileReadError")? {
        return Ok(pinned);
    }
    let pkg = item.package.as_ref().ok_or("missingPackage")?;
    Ok(config.join("packages").join(&item.id).join(&pkg.filename))
}

pub fn verified(config: &Path, item: &ModEntry) -> Result<PathBuf, String> {
    let pkg = item.package.as_ref().ok_or("missingPackage")?;
    let path = existing(config, item)?;
    if !path.try_exists().map_err(|_| "fileReadError")? {
        return Err("downloadFirst".into());
    }
    let fp = file_fingerprint(&path)?;
    if fp.size != pkg.size || fp.sha256 != pkg.sha256 {
        return Err("packageCorrupt".into());
    }
    Ok(path)
}

pub fn clear(config: &Path, item: &ModEntry) -> Result<(), String> {
    let pinned = destination(config, item)?;
    if pinned.try_exists().map_err(|_| "fileReadError")? {
        fs::remove_file(pinned).map_err(|_| "fileWriteError")?;
    }
    // A filename in the old cache may belong to another release.
    if let Ok(legacy) = verified(config, item) {
        fs::remove_file(legacy).map_err(|_| "fileWriteError")?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::{Digest, Sha256};

    #[test]
    fn legacy_cache_and_two_releases_with_the_same_filename() {
        let root = tempfile::tempdir().unwrap();
        let config = root.path();
        let mut item = crate::catalog::entry("overtime").unwrap();
        let pkg = item.package.as_mut().unwrap();
        pkg.sha256 = hex::encode(Sha256::digest(b"one"));
        pkg.size = 3;
        let legacy = existing(config, &item).unwrap();
        fs::create_dir_all(legacy.parent().unwrap()).unwrap();
        fs::write(&legacy, b"one").unwrap();
        assert_eq!(verified(config, &item).unwrap(), legacy);
        let mut next = item.clone();
        next.package.as_mut().unwrap().sha256 = hex::encode(Sha256::digest(b"two"));
        assert_eq!(verified(config, &next).unwrap_err(), "packageCorrupt");
        let pin = destination(config, &next).unwrap();
        fs::create_dir_all(pin.parent().unwrap()).unwrap();
        fs::write(&pin, b"two").unwrap();
        assert_eq!(verified(config, &next).unwrap(), pin);
        clear(config, &next).unwrap();
        assert_eq!(verified(config, &item).unwrap(), legacy);
    }
}
