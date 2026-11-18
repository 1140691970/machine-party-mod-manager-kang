use serde::Deserialize;

const BUNDLED: &str = include_str!("../../../../catalog/mods.json");
const SCHEMA: u32 = 1;

#[derive(Deserialize)]
struct Catalog {
    schema: u32,
    mods: Vec<Entry>,
}

#[derive(Deserialize)]
struct Entry {
    repo: String,
}

/// The catalog shipped with this build, passed to the UI unchanged.
pub fn bundled() -> serde_json::Value {
    serde_json::from_str(BUNDLED).expect("catalog/mods.json is validated by tests")
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
}
