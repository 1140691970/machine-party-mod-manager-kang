// Steam's validation URI is asynchronous. Only consume complete records appended after launch.
use super::*;
use std::io::{BufRead, BufReader, Seek, SeekFrom};

pub fn directory_id(dir: &Path) -> Result<file_id::FileId, String> {
    file_id::get_file_id(dir).map_err(|_| "invalidGame".into())
}

pub fn target(root: &Path) -> Result<(PathBuf, PathBuf), String> {
    let selected = resolve_pck_dir(root).ok_or("invalidGame")?;
    let mut matches = Vec::new();
    for steam in steamlocate::locate_all().map_err(|_| "steamRestoreCopy")? {
        for library in steam.libraries().map_err(|_| "steamRestoreCopy")? {
            let library = library.map_err(|_| "steamRestoreCopy")?;
            if let Some(app) = library.app(STEAM_APP_ID) {
                let install = library.resolve_app_dir(&app.map_err(|_| "steamRestoreCopy")?);
                matches.push((resolve_pck_dir(&install), steam.path().to_owned()));
            }
        }
    }
    match matches.as_slice() {
        [(Some(dir), steam)] if directory_id(dir)? == directory_id(&selected)? => {
            Ok((selected, steam.clone()))
        }
        _ => Err("steamRestoreCopy".into()),
    }
}

#[derive(Default)]
struct Verification {
    started: bool,
    validating: bool,
    fully_installed: bool,
}

impl Verification {
    fn observe(&mut self, line: &str) -> Result<bool, String> {
        let Some((_, msg)) = line.trim_end().split_once("] ") else {
            return Ok(false);
        };
        if msg == "Start validating appID 4108000"
            || msg.starts_with("Start validating appID 4108000 on BuildID ")
        {
            self.started = true;
            self.validating = false;
            self.fully_installed = false;
        }
        let Some(event) = msg.strip_prefix("AppID 4108000 ") else {
            return Ok(false);
        };
        if self.started {
            if let Some(states) = event
                .strip_prefix("App ")
                .unwrap_or(event)
                .strip_prefix("update changed : ")
            {
                self.validating |= states
                    .split(',')
                    .any(|s| matches!(s.trim(), "Validating" | "Verifying Installed"));
            }
            if let Some(states) = event.strip_prefix("state changed : ") {
                self.fully_installed = states.trim_end_matches(',').trim() == "Fully Installed";
            }
            if event.starts_with("update canceled") || event.starts_with("scheduler finished") {
                if self.validating
                    && self.fully_installed
                    && event
                        .starts_with("scheduler finished : removed from schedule (result No Error,")
                {
                    return Ok(true);
                }
                return Err("steamRestoreUnconfirmed".into());
            }
        }
        Ok(false)
    }
}

pub fn wait(
    steam: &Path,
    cancelled: impl Fn() -> bool,
    launch: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    let path = steam.join("logs/content_log.txt");
    let error = |_| "steamRestoreUnconfirmed".to_owned();
    let id = file_id::get_file_id(&path).map_err(error)?;
    let mut log = BufReader::new(fs::File::open(&path).map_err(error)?);
    let mut offset = log.seek(SeekFrom::End(0)).map_err(error)?;
    if cancelled() {
        return Err("steamRestoreCancelled".into());
    }
    launch()?;
    let mut check = Verification::default();
    let mut line = Vec::new();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3600);
    while std::time::Instant::now() < deadline {
        if cancelled() {
            return Err("steamRestoreCancelled".into());
        }
        if file_id::get_file_id(&path).map_err(error)? != id
            || fs::metadata(&path).map_err(error)?.len() < offset
        {
            break;
        }
        let n = log.read_until(b'\n', &mut line).map_err(error)?;
        offset += n as u64;
        if line.ends_with(b"\n") {
            if check.observe(&String::from_utf8_lossy(&line))? {
                return Ok(());
            }
            line.clear();
        } else if line.len() > 64 * 1024 {
            break;
        } else {
            std::thread::sleep(std::time::Duration::from_millis(750));
        }
    }
    Err("steamRestoreUnconfirmed".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    const BEGIN: &str = "[now] Start validating appID 4108000 on BuildID 362";
    const VALIDATE: &str =
        "[now] AppID 4108000 App update changed : Running Update,Verifying Installed,";
    const SUCCESS: &str = "[now] AppID 4108000 scheduler finished : removed from schedule (result No Error, state 0x4)";
    #[test]
    fn requires_new_matching_validation_and_explicit_success() {
        let mut check = Verification::default();
        for line in [
            SUCCESS,
            VALIDATE,
            BEGIN,
            VALIDATE,
            "[now] AppID 4108000 state changed : Fully Installed,",
            &SUCCESS.replace("4108000", "42"),
        ] {
            assert!(!check.observe(line).unwrap());
        }
        assert!(check.observe(SUCCESS).unwrap());
        assert!(
            check
                .observe(&SUCCESS.replace("No Error", "Canceled"))
                .is_err()
        );
    }
    #[test]
    fn old_success_cannot_authorize_a_new_failed_request() {
        use std::io::Write;
        let temp = tempfile::tempdir().unwrap();
        fs::create_dir(temp.path().join("logs")).unwrap();
        let path = temp.path().join("logs/content_log.txt");
        fs::write(&path, format!("{BEGIN}\n{VALIDATE}\n{SUCCESS}\n")).unwrap();
        let result = wait(
            temp.path(),
            || false,
            || {
                let mut log = fs::OpenOptions::new().append(true).open(path).unwrap();
                writeln!(
                    log,
                    "{BEGIN}\n{VALIDATE}\n[now] AppID 4108000 update canceled : Disk write failure"
                )
                .unwrap();
                Ok(())
            },
        );
        assert_eq!(result.unwrap_err(), "steamRestoreUnconfirmed");
    }
}
