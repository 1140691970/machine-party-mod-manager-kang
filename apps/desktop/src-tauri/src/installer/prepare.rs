//! Convert a fingerprint-verified release into an isolated loader-files staging directory.
use super::{collect_dir_fingerprints, extract_zip, file_fingerprint, validate_rel_components};
use crate::catalog::BaselineSpec;
use std::{
    collections::BTreeSet,
    fs::{self, File},
    io::Write,
    path::Path,
};
use zip::{ZipWriter, write::SimpleFileOptions};

type Result<T> = std::result::Result<T, String>;
const CORRUPT: &str = "packageCorrupt";
const WRITE: &str = "fileWriteError";

fn put(pack: &mut ZipWriter<File>, name: &str, bytes: &[u8]) -> Result<()> {
    pack.start_file(
        name,
        SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored),
    )
    .map_err(|_| WRITE)?;
    pack.write_all(bytes).map_err(|_| WRITE.into())
}

pub(super) fn from_source(
    rule: &str,
    archive: &Path,
    output: &Path,
    baseline: &BaselineSpec,
) -> Result<()> {
    let temp = tempfile::tempdir().map_err(|_| WRITE)?;
    extract_zip(archive, temp.path())?;
    fs::create_dir_all(output).map_err(|_| WRITE)?;
    match rule {
        "overtime-manifest-v1" => overtime(temp.path(), output, baseline),
        "binary-tree-v1" => tree(temp.path(), output, false),
        "broadcast-tree-v1" => tree(temp.path(), output, true),
        _ => Err("unsupportedAdapter".into()),
    }
}

fn tree(source: &Path, output: &Path, broadcast: bool) -> Result<()> {
    let root = source.join("mod");
    let files = collect_dir_fingerprints(&root)?;
    let (id, version, count) = if broadcast {
        ("broadcast-8p-freecam", "0.91", 65)
    } else {
        ("binary1936-8p", "1.5", 56)
    };
    if files.len() != count {
        return Err(CORRUPT.into());
    }
    let mut pack = ZipWriter::new(File::create(output.join("overlay.zip")).map_err(|_| WRITE)?);
    for name in files.keys() {
        if ![".gd", ".tscn", ".tres"]
            .iter()
            .any(|ext| name.ends_with(ext))
        {
            return Err(CORRUPT.into());
        }
        put(
            &mut pack,
            name,
            &fs::read(root.join(name)).map_err(|_| CORRUPT)?,
        )?;
        put(
            &mut pack,
            &format!("{name}.remap"),
            format!("[remap]\n\npath=\"res://{name}\"\n").as_bytes(),
        )?;
    }
    pack.finish().map_err(|_| WRITE)?;
    let manifest = serde_json::json!({"id":id,"name":id,"version":version,"entry":"main.gd","priority":-1000,"requires":[]});
    fs::write(output.join("mod.json"), manifest.to_string()).map_err(|_| WRITE)?;
    let entry = include_str!("../../assets/recipes/resource_tree.gd").replace("__MOD_ID__", id);
    fs::write(output.join("main.gd"), entry).map_err(|_| WRITE)?;
    if broadcast {
        let dir = output.join("launchers");
        fs::create_dir(&dir).map_err(|_| WRITE)?;
        for name in [
            "director_hd.ps1",
            "Director2K.cmd",
            "DirectorHD.cmd",
            "DirectorInternal1080Host.cmd",
            "DirectorInternal2KHost.cmd",
            "DirectorMaxQualityHost.cmd",
        ] {
            fs::copy(source.join(name), dir.join(name)).map_err(|_| CORRUPT)?;
        }
        for (name, args) in [
            ("LocalTest8.cmd", "8"),
            ("LocalTest4.cmd", "4"),
            (
                "LocalTestDirectorHD.cmd",
                "8 -DirectorRender 1080 -ClientRender 360",
            ),
            ("StopLocalTest.cmd", "-Stop"),
        ] {
            let command = format!(
                "@echo off\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0localtest.ps1\" {args}\r\nexit /b %ERRORLEVEL%\r\n"
            );
            fs::write(dir.join(name), command).map_err(|_| WRITE)?;
        }
        fs::write(
            dir.join("localtest.ps1"),
            include_bytes!("../../assets/recipes/broadcast/localtest.ps1"),
        )
        .map_err(|_| WRITE)?;
    } else {
        fs::write(
            output.join("NOTICE.md"),
            include_bytes!("../../assets/recipes/binary1936/NOTICE.md"),
        )
        .map_err(|_| WRITE)?;
    }
    Ok(())
}

fn overtime(source: &Path, output: &Path, baseline: &BaselineSpec) -> Result<()> {
    let inner = source.join("payload");
    extract_zip(&source.join("overtime_payload.zip"), &inner)?;
    let text = fs::read_to_string(inner.join("manifest.txt")).map_err(|_| CORRUPT)?;
    let mut lines = text.lines();
    for expected in [
        "OVERTIME-PAYLOAD\t1".to_string(),
        "mod_tag\tovertime-1.7".into(),
        "game_version\tv2.1.2".into(),
        format!("vanilla_sha256\t{}", baseline.sha256.to_uppercase()),
        format!("vanilla_size\t{}", baseline.size),
    ] {
        if lines.next() != Some(&expected) {
            return Err(CORRUPT.into());
        }
    }
    let mut guard: serde_json::Value = serde_json::from_str(include_str!(
        "../../assets/recipes/overtime/vanilla_md5.json"
    ))
    .map_err(|_| CORRUPT)?;
    let originals = guard["files"].as_object().ok_or(CORRUPT)?;
    let mut seen = BTreeSet::new();
    let overlay = output.join("overtime_overlay.zip");
    let mut pack = ZipWriter::new(File::create(&overlay).map_err(|_| WRITE)?);
    for line in lines {
        let fields: Vec<_> = line.split('\t').collect();
        let ["file", res, input, size, sha] = fields.as_slice() else {
            return Err(CORRUPT.into());
        };
        if !originals.contains_key(*res) || !seen.insert(*res) {
            return Err(CORRUPT.into());
        }
        let name = res.strip_prefix("res://").ok_or(CORRUPT)?;
        let path = inner.join(validate_rel_components(input)?);
        let fp = file_fingerprint(&path)?;
        if Some(fp.size) != size.parse().ok() || !fp.sha256.eq_ignore_ascii_case(sha) {
            return Err(CORRUPT.into());
        }
        put(&mut pack, name, &fs::read(path).map_err(|_| CORRUPT)?)?;
    }
    if seen.len() != originals.len() {
        return Err(CORRUPT.into());
    }
    pack.finish().map_err(|_| WRITE)?;
    let fp = file_fingerprint(&overlay)?;
    guard["overlay_size"] = fp.size.into();
    guard["overlay_sha256"] = fp.sha256.into();
    fs::write(output.join("vanilla_md5.json"), guard.to_string()).map_err(|_| WRITE)?;
    for (name, data) in [
        (
            "main.gd",
            include_str!("../../assets/recipes/overtime/main.gd"),
        ),
        (
            "mod.json",
            include_str!("../../assets/recipes/overtime/mod.json"),
        ),
        (
            "LICENSE",
            include_str!("../../assets/recipes/overtime/LICENSE"),
        ),
    ] {
        fs::write(output.join(name), data).map_err(|_| WRITE)?;
    }
    fs::copy(source.join("BUILDINFO.json"), output.join("BUILDINFO.json")).map_err(|_| CORRUPT)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        catalog,
        installer::{SystemRunner, stage_package},
    };
    use std::path::PathBuf;

    #[test]
    #[ignore = "requires pinned release ZIPs in MPM_SOURCE_FIXTURES"]
    fn all_release_archives_match_prepared_files() {
        let fixtures = PathBuf::from(std::env::var_os("MPM_SOURCE_FIXTURES").unwrap());
        for item in catalog::all_entries() {
            let pkg = item.package.unwrap();
            let adapter = item.adapter.unwrap();
            let tmp = tempfile::tempdir().unwrap();
            let archive = fixtures.join(&pkg.filename);
            let raw = tmp.path().join("raw");
            let out = tmp.path().join("staged");
            stage_package(&archive, &out, &pkg, &adapter, tmp.path(), &SystemRunner)
                .unwrap_or_else(|error| panic!("{}: {error}", pkg.filename));
            extract_zip(&archive, &raw).unwrap();
            match adapter.source_rule.as_deref() {
                Some("overtime-manifest-v1") => {
                    let official = tmp.path().join("official");
                    extract_zip(
                        &fixtures.join("Machine-Party-Overtime-1.7-MPML.zip"),
                        &official,
                    )
                    .unwrap();
                    let original = tmp.path().join("original");
                    extract_zip(&official.join("overtime/overtime_overlay.zip"), &original)
                        .unwrap();
                    let actual = tmp.path().join("actual");
                    extract_zip(&out.join("overtime_overlay.zip"), &actual).unwrap();
                    let expected = collect_dir_fingerprints(&original).unwrap();
                    assert_eq!(expected.len(), 70);
                    assert_eq!(collect_dir_fingerprints(&actual).unwrap(), expected);
                }
                Some(_) => {
                    let actual = tmp.path().join("actual");
                    extract_zip(&out.join("overlay.zip"), &actual).unwrap();
                    let files = collect_dir_fingerprints(&raw.join("mod")).unwrap();
                    assert_eq!(
                        collect_dir_fingerprints(&actual).unwrap().len(),
                        files.len() * 2
                    );
                    for (name, fp) in files {
                        assert_eq!(file_fingerprint(&actual.join(&name)).unwrap(), fp);
                        assert_eq!(
                            fs::read_to_string(actual.join(format!("{name}.remap"))).unwrap(),
                            format!("[remap]\n\npath=\"res://{name}\"\n")
                        );
                    }
                    if item.id == "broadcast-8p-freecam" {
                        assert_eq!(
                            fs::read(out.join("launchers/localtest.ps1")).unwrap(),
                            include_bytes!("../../assets/recipes/broadcast/localtest.ps1")
                        );
                        assert_eq!(fs::read_dir(out.join("launchers")).unwrap().count(), 11);
                    } else {
                        assert!(out.join("NOTICE.md").is_file());
                    }
                }
                None => assert_eq!(
                    collect_dir_fingerprints(&raw).unwrap(),
                    collect_dir_fingerprints(&out).unwrap()
                ),
            }
        }
    }
}
