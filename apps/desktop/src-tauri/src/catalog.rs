use serde::{Deserialize, Serialize};

const BUNDLED: &str = include_str!("../../../../catalog/mods.json");
const SCHEMA: u32 = 1;

fn default_true() -> bool {
    true
}

#[derive(Deserialize)]
struct Catalog {
    schema: u32,
    mods: Vec<ModEntry>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ModEntry {
    pub id: String,
    pub order: u32,
    pub repo: String,
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
    pub kind: String,
    pub platforms: Vec<String>,
    pub target: String,
    pub touches: Vec<String>,
    pub exclusive: String,
    pub baseline: BaselineSpec,
    #[serde(default, rename = "requiredFiles")]
    pub required_files: Vec<String>,
    #[serde(rename = "verifyFiles")]
    pub verify_files: Option<String>,
    #[serde(rename = "upstreamUninstall", default = "default_true")]
    pub upstream_uninstall: bool,
    pub run: RunSpec,
    pub actions: ActionSpec,
    pub status: StatusMatchers,
    #[serde(rename = "forbiddenArgs")]
    pub forbidden_args: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct BaselineSpec {
    pub file: String,
    pub size: u64,
    pub sha256: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct RunSpec {
    pub interpreter: String,
    pub program: String,
    pub common: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct ActionSpec {
    pub preflight: Vec<String>,
    pub status: Vec<String>,
    pub install: Vec<String>,
    pub uninstall: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct StatusMatchers {
    pub installed: String,
    pub vanilla: String,
    pub older: Option<String>,
}

/// The catalog shipped with this build, passed to the UI unchanged.
pub fn bundled() -> serde_json::Value {
    serde_json::from_str(BUNDLED).expect("catalog/mods.json is validated by tests")
}

/// A preview can exercise only the exact adapter and package embedded in that build.
pub fn preview_entry(version: &str) -> Option<serde_json::Value> {
    bundled()["mods"]
        .as_array()?
        .iter()
        .find(|item| {
            item["windowsPreview"].as_str() == Some(version) && item["adapter"].is_object()
        })
        .cloned()
}

pub fn matches_preview(request: &ModEntry, version: &str) -> bool {
    preview_entry(version)
        .and_then(|entry| serde_json::from_value::<ModEntry>(entry).ok())
        .as_ref()
        == Some(request)
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

/// Author pages may only be opened for repositories listed in the bundled catalog.
pub fn project_url(repo: &str) -> Option<String> {
    let catalog: Catalog = serde_json::from_str(BUNDLED).ok()?;
    if catalog.schema != SCHEMA {
        return None;
    }
    catalog
        .mods
        .iter()
        .any(|entry| entry.repo == repo)
        .then(|| format!("https://github.com/{repo}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_requires_matching_build_and_pinned_package() {
        let mut item = entry("overtime").unwrap();
        assert!(matches_preview(&item, "0.1.2-3"));
        assert!(!matches_preview(&item, "0.1.2"));
        item.package.as_mut().unwrap().sha256.clear();
        assert!(!matches_preview(&item, "0.1.2-3"));
    }

    #[test]
    fn bundled_catalog_parses_with_unique_repositories() {
        let catalog: Catalog = serde_json::from_str(BUNDLED).unwrap();
        assert_eq!(catalog.schema, SCHEMA);
        let mut repos: Vec<_> = catalog.mods.iter().map(|entry| &entry.repo).collect();
        repos.sort();
        repos.dedup();
        assert_eq!(repos.len(), catalog.mods.len());
        assert!(bundled().is_object());
    }

    #[test]
    fn only_listed_projects_can_be_opened() {
        assert_eq!(
            project_url("DarkJadeStone/MachineParty-Overtime").as_deref(),
            Some("https://github.com/DarkJadeStone/MachineParty-Overtime")
        );
        assert_eq!(project_url("evil/repo"), None);
        assert_eq!(
            project_url("DarkJadeStone/MachineParty-Overtime/../x"),
            None
        );
    }

    #[test]
    fn overtime_entry_deserializes_package_and_adapter() {
        let mod_entry = entry("overtime").expect("overtime entry present");
        assert_eq!(mod_entry.repo, "DarkJadeStone/MachineParty-Overtime");
        assert_eq!(mod_entry.version.as_deref(), Some("v1.7"));
        let pkg = mod_entry.package.as_ref().expect("package present");
        assert_eq!(pkg.asset_id, "594522625");
        assert_eq!(pkg.size, 854_623);
        let adapter = mod_entry.adapter.as_ref().expect("adapter present");
        assert_eq!(adapter.kind, "upstream-cli");
        assert_eq!(adapter.exclusive, "pck");
        assert!(adapter.upstream_uninstall);
        assert_eq!(adapter.run.program, "overtime_install.exe");
        assert!(adapter.forbidden_args.contains(&"--force".to_string()));
        assert!(parse_entry(BUNDLED, "missing").is_err());

        let entries = all_entries();
        assert!(!entries.is_empty());
        assert_eq!(
            download_url(&mod_entry).unwrap(),
            "https://machineparty.ailaogong.men/v1/downloads/overtime/v1.7/594522625"
        );
    }
}
