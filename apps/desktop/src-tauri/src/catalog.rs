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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preview_requires_matching_build_and_pinned_package() {
        assert_eq!(preview_entries("0.1.2-6").len(), 5);
        for id in [
            "overtime",
            "machineparty-plus",
            "broadcast-8p-freecam",
            "binary1936-8p",
            "roller-carnival",
        ] {
            let mut item = entry(id).unwrap();
            assert!(matches_preview(&item, "0.1.2-6"), "{id}");
            assert!(!matches_preview(&item, "0.1.2"), "{id}");
            item.package.as_mut().unwrap().sha256.clear();
            assert!(!matches_preview(&item, "0.1.2-6"), "{id}");
        }
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
        assert_eq!(pkg.asset_id, "594522622");
        assert_eq!(pkg.filename, "Machine-Party-Overtime-1.7-MPML.zip");
        assert_eq!(pkg.size, 830_277);
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

        let broadcast = entry("broadcast-8p-freecam").expect("broadcast entry present");
        let broadcast_adapter = broadcast.adapter.as_ref().unwrap();
        assert_eq!(broadcast_adapter.kind, "upstream-cli");
        assert_eq!(broadcast_adapter.exclusive, "pck");
        assert!(!broadcast_adapter.auto_loader);
        assert_eq!(broadcast_adapter.run.interpreter, "powershell");
        assert!(
            broadcast_adapter
                .forbidden_args
                .contains(&"--force".to_string())
        );

        let b8p = entry("binary1936-8p").expect("binary1936-8p entry present");
        assert_eq!(
            b8p.adapter.as_ref().unwrap().run.interpreter,
            "bundled-python"
        );

        let entries = all_entries();
        assert_eq!(entries.len(), 5);
        let roller = entry("roller-carnival").expect("roller-carnival entry present");
        assert_eq!(roller.repo, "JamesGZM/machine-party-mod-manager");
        let roller_pkg = roller
            .package
            .as_ref()
            .expect("roller-carnival package present");
        assert_eq!(roller_pkg.filename, "roller-carnival-0.1.0.zip");
        assert!(roller_pkg.mirror_approved);
        assert!(roller.adapter.as_ref().unwrap().auto_loader);
        assert_eq!(
            project_url("JamesGZM/machine-party-mod-manager").as_deref(),
            Some("https://github.com/JamesGZM/machine-party-mod-manager")
        );
        assert_eq!(
            download_url(&mod_entry).unwrap(),
            "https://machineparty.ailaogong.men/v1/downloads/overtime/v1.7/594522622"
        );
        assert_eq!(
            download_url(&roller).unwrap(),
            "https://machineparty.ailaogong.men/v1/downloads/roller-carnival/v0.1.0/1001"
        );
    }
}
