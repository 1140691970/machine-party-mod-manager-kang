use std::{
    fs::{File, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

#[cfg(not(windows))]
use std::io::Read;
#[cfg(windows)]
use std::os::windows::{fs::OpenOptionsExt, process::CommandExt};

#[cfg(windows)]
use crate::game;

/// Request passed to an external process runner.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandRequest {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub cwd: PathBuf,
}

/// Captured output from an external command execution.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandOutput {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

/// Abstracts subprocess invocation for L1 unit simulation vs. L2/production execution.
pub trait ProcessRunner {
    fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String>;
}

/// Real OS subprocess runner with stdin closed to prevent interactive hangs.
pub struct SystemRunner;

#[cfg(not(windows))]
fn is_pe_executable(path: &Path) -> bool {
    let Ok(mut file) = File::open(path) else {
        return false;
    };
    let mut magic = [0u8; 2];
    file.read_exact(&mut magic).is_ok() && magic == *b"MZ"
}

impl ProcessRunner for SystemRunner {
    fn run(&self, req: &CommandRequest) -> Result<CommandOutput, String> {
        #[cfg(not(windows))]
        let mut cmd = if is_pe_executable(&req.program) {
            let mut mono = Command::new("mono");
            mono.arg(&req.program);
            mono
        } else {
            Command::new(&req.program)
        };
        #[cfg(windows)]
        let mut cmd = Command::new(&req.program);
        #[cfg(windows)]
        cmd.creation_flags(0x08000000);

        let mut child = cmd
            .args(&req.args)
            .current_dir(&req.cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("processSpawnFailed: {e}"))?;
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(b"y\n");
        }
        let output = child
            .wait_with_output()
            .map_err(|e| format!("processSpawnFailed: {e}"))?;
        Ok(CommandOutput {
            code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

/// Checks whether the target game copy is currently locked or running.
pub trait GameLockCheck {
    fn ensure_unlocked(&self, pck_dir: &Path, pck_path: &Path) -> Result<(), String>;
}

/// OS-level lock and writability check for the target PCK file.
pub struct SystemGameLockCheck;

impl GameLockCheck for SystemGameLockCheck {
    fn ensure_unlocked(&self, _pck_dir: &Path, pck_path: &Path) -> Result<(), String> {
        if !pck_path.is_file() {
            return Err("invalidGame".into());
        }
        let mut opts = OpenOptions::new();
        opts.read(true).write(true);
        #[cfg(windows)]
        {
            if !game::process::matching_pids(_pck_dir)?.is_empty() {
                return Err("gameRunning".into());
            }
            opts.share_mode(0);
        }
        match opts.open(pck_path) {
            Ok(_) => Ok(()),
            Err(err) if err.kind() == io::ErrorKind::PermissionDenied => {
                Err("gamePermissionDenied".into())
            }
            Err(_) => Err("gameRunning".into()),
        }
    }
}
