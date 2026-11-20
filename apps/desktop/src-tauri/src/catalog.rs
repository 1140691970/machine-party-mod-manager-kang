pub mod receipts;
use serde::{Deserialize, Serialize};

const BUNDLED: &str = include_str!("../../../../catalog/mods.json");
const SCHEMA: u32 = 1;

fn default_true() -> bool {
    true
}

#[derive(Deserialize)]
struct Catalog {
    schema: u32,
    #[serde(default)]
    repo: Option<String>,
    mods: Vec<ModEntry>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ModEntry {
    pub id: String,
    pub order: u32,
    pub repo: String,
    #[serde(default, rename = "inventoryById")]
    pub inventory_by_id: bool,
    #[serde(
        default,
        rename = "legacyInventoryRepos",
        skip_serializing_if = "Vec::is_empty"
    )]
    pub legacy_inventory_repos: Vec<String>,
    pub version: Option<String>,
    pub verified: bool,
    pub package: Option<PackageSpec>,
    pub adapter: Option<AdapterProfile>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct PackageSpec {
    #[serde(rename = "assetId")]
    pub asset_id: String,
    pub filename: String,
    pub size: u64,
    pub sha256: String,
    #[serde(rename = "mirrorApproved")]
    pub mirror_approved: bool,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct AdapterProfile {
    #[serde(
        default,
        rename = "sourceRule",
        skip_serializing_if = "Option::is_none"
    )]
    pub source_rule: Option<String>,
    #[serde(
        default,
        rename = "conflictGroup",
        skip_serializing_if = "Option::is_none"
    )]
    pub conflict_group: Option<String>,
    pub kind: String,
    pub platforms: Vec<String>,
    pub target: String,
    pub touches: Vec<String>,
    pub exclusive: String,
    #[serde(default, rename = "autoLoader")]
    pub auto_loader: bool,
    pub baseline: BaselineSpec,
    #[serde(default, rename = "requiredFiles")]
    pub required_files: Vec<String>,
    #[serde(rename = "verifyFiles")]
    pub verify_files: Option<String>,
    #[serde(rename = "upstreamUninstall", default = "default_true")]
    pub upstream_uninstall: bool,
    #[serde(default)]
    pub run: RunSpec,
    #[serde(default)]
    pub actions: ActionSpec,
    #[serde(default)]
    pub status: StatusMatchers,
    #[serde(default, rename = "forbiddenArgs")]
    pub forbidden_args: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct BaselineSpec {
    pub file: String,
    pub size: u64,
    pub sha256: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct RunSpec {
    pub interpreter: String,
    pub program: String,
    pub common: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct ActionSpec {
    pub preflight: Vec<String>,
    pub status: Vec<String>,
    pub install: Vec<String>,
    pub uninstall: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq, Eq)]
pub struct StatusMatchers {
    pub installed: String,
    pub vanilla: String,
    pub older: Option<String>,
}

impl ModEntry {
    pub fn inventory_key(&self) -> &str {
        if self.inventory_by_id || !self.legacy_inventory_repos.is_empty() {
            &self.id
        } else {
            &self.repo
        }
    }
}

/// The catalog shipped with this build, passed to the UI unchanged.
pub fn bundled() -> serde_json::Value {
    serde_json::from_str(BUNDLED).expect("catalog/mods.json is validated by tests")
}

/// Previews can exercise only the exact adapters and packages embedded in that build.
pub fn preview_entries(version: &str) -> Vec<serde_json::Value> {
    bundled()["mods"]
        .as_array()
        .map(|mods| {
            mods.iter()
                .filter(|item| {
                    item["windowsPreview"].as_str() == Some(version) && item["adapter"].is_object()
                })
                .cloned()
                .collect()
        })
        .unwrap_or_default()
}

/// A preview can exercise only the exact adapter and package embedded in that build.
pub fn preview_entry(version: &str) -> Option<serde_json::Value> {
    preview_entries(version).into_iter().next()
}

pub fn matches_preview(request: &ModEntry, version: &str) -> bool {
    preview_entries(version)
        .into_iter()
        .filter_map(|entry| serde_json::from_value::<ModEntry>(entry).ok())
        .any(|entry| &entry == request)
}

/// Returns all entries from the bundled catalog.
pub fn all_entries() -> Vec<ModEntry> {
    let catalog: Catalog =
        serde_json::from_str(BUNDLED).expect("catalog/mods.json is validated by tests");
    if catalog.schema != SCHEMA {
        return Vec::new();
    }
    catalog.mods
}

/// Builds the approved Worker download URL for one catalog mod entry.
pub fn download_url(mod_entry: &ModEntry) -> Result<String, String> {
    let version = mod_entry
        .version
        .as_deref()
        .filter(|v| !v.is_empty())
        .ok_or("missingPackage")?;
    let pkg = mod_entry.package.as_ref().ok_or("missingPackage")?;
    if !pkg.mirror_approved
        || pkg.asset_id.is_empty()
        || !pkg.asset_id.bytes().all(|b| b.is_ascii_digit())
    {
        return Err("missingPackage".into());
    }
    Ok(format!(
        "https://machineparty.ailaogong.men/v1/downloads/{}/{version}/{}",
        mod_entry.id, pkg.asset_id
    ))
}

/// Looks up one mod entry by ID from a catalog JSON snapshot.
#[allow(dead_code)] // Wired into Stage 3 Tauri commands; exercised by unit tests.
pub fn parse_entry(catalog_json: &str, id: &str) -> Result<ModEntry, String> {
    let catalog: Catalog =
        serde_json::from_str(catalog_json).map_err(|_| "catalogUnavailable".to_string())?;
    if catalog.schema != SCHEMA {
        return Err("catalogUnavailable".into());
    }
    catalog
        .mods
        .into_iter()
        .find(|entry| entry.id == id)
        .ok_or_else(|| "unknownMod".into())
}

/// Looks up one mod entry by ID from the bundled catalog.
#[allow(dead_code)] // Wired into Stage 3 Tauri commands; exercised by unit tests.
pub fn entry(id: &str) -> Option<ModEntry> {
    parse_entry(BUNDLED, id).ok()
}

/// Author pages and the app repository may only be opened when listed in the bundled catalog.
pub fn project_url(repo: &str) -> Option<String> {
    let catalog: Catalog = serde_json::from_str(BUNDLED).ok()?;
    if catalog.schema != SCHEMA {
        return None;
    }
    if catalog.repo.as_deref() == Some(repo) {
        return Some(format!("https://github.com/{repo}"));
    }
    catalog
        .mods
        .iter()
        .any(|entry| entry.repo == repo)
        .then(|| format!("https://github.com/{repo}"))
}

pub fn legacy_entry(item: &ModEntry) -> Option<ModEntry> {
    let overrides: serde_json::Value =
        serde_json::from_str(include_str!("../../../../catalog/legacy-adapters.json")).ok()?;
    let old = overrides.get(&item.id)?;
    let mut entry = item.clone();
    entry.version = Some(old["version"].as_str()?.into());
    entry.adapter = Some(serde_json::from_value(old["adapter"].clone()).ok()?);
    entry.package = Some(serde_json::from_value(old["package"].clone()).ok()?);
    Some(entry)
}

pub fn numeric_version(version: &str) -> Option<Vec<u64>> {
    let parts = version.trim_start_matches(['v', 'V']);
    if parts.len() > 64 || version.len() - parts.len() > 1 {
        return None;
    }
    let mut parsed = parts
        .split('.')
        .map(|n| {
            if n.is_empty() || !n.bytes().all(|c| c.is_ascii_digit()) {
                return None;
            }
            n.parse().ok()
        })
        .collect::<Option<Vec<u64>>>()?;
    while parsed.last() == Some(&0) {
        parsed.pop();
    }
    Some(parsed)
}

pub fn newer(version: &str, installed: &str) -> bool {
    numeric_version(version)
        .zip(numeric_version(installed))
        .is_some_and(|(a, b)| a > b)
}

pub fn signed_updates(
    document: &str,
    signature: &str,
    key: &str,
    preview: bool,
) -> Result<Vec<ModEntry>, String> {
    use base64::{Engine, engine::general_purpose::STANDARD};
    use minisign_verify::{PublicKey, Signature};
    let invalid = "catalogInvalid";
    if document.len() > 1024 * 1024 || signature.len() > 4096 {
        return Err(invalid.into());
    }
    let decode = |s: &str| {
        String::from_utf8(STANDARD.decode(s.trim()).map_err(|_| invalid)?).map_err(|_| invalid)
    };
    PublicKey::decode(&decode(key)?)
        .map_err(|_| invalid)?
        .verify(
            format!("machine-party-mod-catalog-v1\n{document}").as_bytes(),
            &Signature::decode(&decode(signature)?).map_err(|_| invalid)?,
            false,
        )
        .map_err(|_| invalid)?;
    approved_updates(document, preview)
}

// A signed first-party entry can reuse an existing native loader profile.
// Only its package file list varies. Paths, baseline and installer behavior stay pinned.
fn compatible_native(remote: &ModEntry, template: &ModEntry) -> bool {
    let (Some(profile), Some(mut known)) = (&remote.adapter, template.adapter.clone()) else {
        return false;
    };
    known.required_files.clone_from(&profile.required_files);
    known.kind == "loader-files"
        && known.source_rule.is_none()
        && known == *profile
        && crate::installer::validate_adapter(profile).is_ok()
}

fn approved_updates(document: &str, preview: bool) -> Result<Vec<ModEntry>, String> {
    let data: serde_json::Value = serde_json::from_str(document).map_err(|_| "catalogInvalid")?;
    if data["schema"].as_u64() != Some(1) {
        return Err("catalogInvalid".into());
    }
    let mut approved = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    let known = all_entries();
    let project = bundled()["repo"].as_str().unwrap_or("").to_owned();
    for raw in data["mods"].as_array().ok_or("catalogInvalid")? {
        let id = raw["id"].as_str().ok_or("catalogInvalid")?;
        if !seen.insert(id) {
            return Err("catalogInvalid".into());
        }
        let remote: ModEntry = serde_json::from_value(raw.clone()).map_err(|_| "catalogInvalid")?;
        let Some(pkg) = remote.package.as_ref() else {
            continue;
        };
        let version = remote.version.as_deref().unwrap_or("");
        let existing = known.iter().find(|local| local.id == id);
        if let Some(local) = existing {
            let same = local.version == remote.version && local.package == remote.package;
            if (!same && !newer(version, local.version.as_deref().unwrap_or("")))
                || local.repo != remote.repo
                || local.inventory_key() != remote.inventory_key()
                || local.legacy_inventory_repos != remote.legacy_inventory_repos
                || !compatible_native(&remote, local)
            {
                continue;
            }
        } else if !remote.inventory_by_id
            || !remote.legacy_inventory_repos.is_empty()
            || remote.repo != project
            || !crate::installer::is_safe_filename(id)
            || id.len() > 80
            || !id
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
            || !known
                .iter()
                .any(|local| local.repo == remote.repo && compatible_native(&remote, local))
        {
            continue;
        }
        if !(remote.verified || preview && raw["updateChannel"] == "preview")
            || numeric_version(version).is_none()
            || !pkg.mirror_approved
            || pkg.size == 0
            || !crate::installer::is_hex_sha256(&pkg.sha256)
            || !pkg.filename.ends_with(".zip")
            || pkg.filename.contains("..")
            || !pkg
                .filename
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
            || pkg.asset_id.is_empty()
            || !pkg.asset_id.bytes().all(|b| b.is_ascii_digit())
        {
            continue;
        }
        approved.push(remote);
    }
    Ok(approved)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detached_catalog_signature_binds_the_exact_document() {
        // Public verification fixture generated with the release signer and a temporary key.
        let key = "dW50cnVzdGVkIGNvbW1lbnQ6IG1pbmlzaWduIHB1YmxpYyBrZXk6IDcwRTNCMjlERjRFMEMxQzQKUldURXdlRDBuYkxqY05iaFF1ejJnTFdOS05ScWN6UHJvMnBTOGYwOWNjYktjWGIyNXljeUdJdkoK";
        let signature = "dW50cnVzdGVkIGNvbW1lbnQ6IHNpZ25hdHVyZSBmcm9tIHRhdXJpIHNlY3JldCBrZXkKUlVURXdlRDBuYkxqY0dEdTZZL01jV0hxMHpzRFEzaE5hWVYzMjJ1ejQ4dnM4TjViRFBScGp6V0xVWDJ1Q3NpZVVmZHo0TW10cmowbFhOWE1qYVZuaUhNWCs0ZmNMUW5aNFFjPQp0cnVzdGVkIGNvbW1lbnQ6IHRpbWVzdGFtcDoxNzk1MDkxOTkyCWZpbGU6Y2F0YWxvZwprcmYwTUVPaEExMlpiSitzd1FSMWxObXIzVFcvS2tUTnFLbFg1K3oweGhuRlhLaTB1MktSeFFVZWRkOFR0SGpwMGxwamFWZDVsNHJyTitzRUpCcHFDQT09Cg==";
        let doc = r#"{"schema":1,"mods":[]}"#;
        assert!(
            signed_updates(doc, signature, key, true)
                .unwrap()
                .is_empty()
        );
        assert!(signed_updates(&format!("{doc} "), signature, key, true).is_err());
        assert!(signed_updates(doc, "", key, true).is_err());
    }

    #[test]
    fn only_compatible_native_packages_can_advance_from_a_signed_catalog() {
        let snapshot = bundled();
        let candidate = |id: &str| {
            let mut m = snapshot["mods"]
                .as_array()
                .unwrap()
                .iter()
                .find(|m| m["id"] == id)
                .unwrap()
                .clone();
            m["version"] = "v9.0".into();
            m["verified"] = false.into();
            m["updateChannel"] = "preview".into();
            m
        };
        let allowed = |m: &serde_json::Value, preview| {
            let doc = serde_json::json!({"schema":1,"mods":[m]}).to_string();
            !approved_updates(&doc, preview).unwrap().is_empty()
        };
        let mut roller = candidate("roller-carnival");
        assert!(allowed(&roller, true));
        assert!(!allowed(&roller, false));
        roller["verified"] = true.into();
        assert!(allowed(&roller, false));
        let mut promoted = roller.clone();
        promoted["version"] = entry("roller-carnival").unwrap().version.unwrap().into();
        assert!(allowed(&promoted, false));
        promoted["package"]["sha256"] = "0".repeat(64).into();
        assert!(!allowed(&promoted, false));
        for (path, value) in [
            ("/version", "v0.0.1"),
            ("/repo", "different/project"),
            ("/package/filename", "../bad.zip"),
            ("/adapter/exclusive", "pck"),
        ] {
            let mut invalid = roller.clone();
            *invalid.pointer_mut(path).unwrap() = value.into();
            assert!(!allowed(&invalid, true));
        }
        assert!(!allowed(&candidate("overtime"), true));
        assert!(!newer("v1.00.0", "1"));
        assert!(!newer("v1.9-beta", "v1.0"));
        assert!(newer("v1.10", "v1.9"));
    }

    #[test]
    fn preview_accepts_new_first_party_native_mods_and_changed_package_file_lists() {
        let snapshot = bundled();
        let mut item = snapshot["mods"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["id"] == "standalone-hd")
            .unwrap()
            .clone();
        let accepts = |m: &serde_json::Value, preview| {
            let doc = serde_json::json!({"schema":1,"mods":[m]}).to_string();
            approved_updates(&doc, preview).unwrap().len() == 1
        };
        item["verified"] = false.into();
        item["updateChannel"] = "preview".into();
        item["version"] = "v0.2.0".into();
        item["adapter"]["requiredFiles"] = serde_json::json!(["mod.json", "main.gd", "extra.gd"]);
        assert!(accepts(&item, true));
        item["id"] = "new-native-hd".into();
        assert!(accepts(&item, true));
        assert!(!accepts(&item, false));
        let mut stable = item.clone();
        stable["verified"] = true.into();
        assert!(accepts(&stable, false));
        for (field, value) in [
            ("/repo", "another/author"),
            ("/id", "../escape"),
            ("/adapter/target", "elsewhere"),
            ("/adapter/baseline/file", "another.pck"),
            ("/adapter/requiredFiles/0", "../file"),
            ("/version", "../0.2"),
            ("/package/filename", "../zip"),
        ] {
            let mut invalid = item.clone();
            *invalid.pointer_mut(field).unwrap() = value.into();
            assert!(!accepts(&invalid, true), "{field}");
        }
    }

    #[test]
    fn preview_requires_matching_build_and_pinned_package() {
        assert_eq!(preview_entries("0.1.2-13").len(), 7);
        for id in [
            "overtime",
            "machineparty-plus",
            "roller-carnival",
            "lobby-bots",
            "standalone-hd",
            "player-spotlight",
            "bubble-blitz",
        ] {
            let mut item = entry(id).unwrap();
            assert!(matches_preview(&item, "0.1.2-13"), "{id}");
            assert!(!matches_preview(&item, "0.1.2"), "{id}");
            item.package.as_mut().unwrap().sha256.clear();
            assert!(!matches_preview(&item, "0.1.2-13"), "{id}");
        }
    }

    #[test]
    fn bundled_catalog_parses_with_unique_inventory_keys() {
        let catalog: Catalog = serde_json::from_str(BUNDLED).unwrap();
        assert_eq!(catalog.schema, SCHEMA);
        let mut keys = std::collections::BTreeSet::new();
        for item in &catalog.mods {
            assert!(keys.insert(item.inventory_key()));
            for repo in &item.legacy_inventory_repos {
                assert!(keys.insert(repo.as_str()), "duplicate inventory key {repo}");
            }
        }
        assert!(bundled().is_object());
    }

    #[test]
    fn only_listed_projects_can_be_opened() {
        assert_eq!(
            project_url("DarkJadeStone/MachineParty-Overtime").as_deref(),
            Some("https://github.com/DarkJadeStone/MachineParty-Overtime")
        );
        assert_eq!(
            project_url("JamesGZM/machine-party-mod-manager").as_deref(),
            Some("https://github.com/JamesGZM/machine-party-mod-manager")
        );
        assert_eq!(project_url("evil/repo"), None);
        assert_eq!(
            project_url("DarkJadeStone/MachineParty-Overtime/../x"),
            None
        );
    }

    #[test]
    fn bundled_entries_deserialize_packages_and_adapters() {
        let mod_entry = entry("overtime").expect("overtime entry present");
        assert_eq!(mod_entry.repo, "DarkJadeStone/MachineParty-Overtime");
        assert_eq!(mod_entry.version.as_deref(), Some("v1.7"));
        let pkg = mod_entry.package.as_ref().expect("package present");
        assert_eq!(pkg.asset_id, "594522625");
        assert_eq!(pkg.filename, "Machine-Party-Overtime-1.7-CLI.zip");
        assert_eq!(pkg.size, 854_623);
        let adapter = mod_entry.adapter.as_ref().expect("adapter present");
        assert_eq!(adapter.kind, "loader-files");
        assert_eq!(adapter.exclusive, "loader");
        assert!(adapter.auto_loader);
        assert!(!adapter.upstream_uninstall);
        assert!(parse_entry(BUNDLED, "missing").is_err());

        let plus = entry("machineparty-plus").expect("plus entry present");
        let plus_adapter = plus.adapter.as_ref().unwrap();
        assert_eq!(plus_adapter.kind, "loader-files");
        assert_eq!(plus_adapter.exclusive, "loader");
        assert!(plus_adapter.auto_loader);

        assert_eq!(all_entries().len(), 7);
        let roller = entry("roller-carnival").expect("roller-carnival entry present");
        assert_eq!(roller.repo, "JamesGZM/machine-party-mod-manager");
        let roller_pkg = roller
            .package
            .as_ref()
            .expect("roller-carnival package present");
        assert_eq!(roller_pkg.filename, "roller-carnival-0.1.6.zip");
        assert!(roller_pkg.mirror_approved);
        assert!(roller.adapter.as_ref().unwrap().auto_loader);

        let bubble = entry("bubble-blitz").expect("bubble-blitz entry present");
        assert_eq!(bubble.repo, "JamesGZM/machine-party-mod-manager");
        let bubble_pkg = bubble
            .package
            .as_ref()
            .expect("bubble-blitz package present");
        assert_eq!(bubble_pkg.filename, "bubble-blitz-0.1.1.zip");
        assert!(bubble_pkg.mirror_approved);
        assert!(bubble.adapter.as_ref().unwrap().auto_loader);
        assert_eq!(
            project_url("JamesGZM/machine-party-mod-manager").as_deref(),
            Some("https://github.com/JamesGZM/machine-party-mod-manager")
        );
        assert_eq!(
            download_url(&mod_entry).unwrap(),
            "https://machineparty.ailaogong.men/v1/downloads/overtime/v1.7/594522625"
        );
        assert_eq!(
            download_url(&roller).unwrap(),
            "https://machineparty.ailaogong.men/v1/downloads/roller-carnival/v0.1.6/1018"
        );
    }
}
