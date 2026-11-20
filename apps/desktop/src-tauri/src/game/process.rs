//! Windows process operations scoped to the executable in one game copy.
use std::{
    ffi::{OsStr, OsString},
    os::windows::{
        ffi::OsStringExt,
        io::{AsHandle, AsRawHandle, BorrowedHandle, FromRawHandle, OwnedHandle},
    },
    path::Path,
};
use sysinfo::{ProcessRefreshKind, RefreshKind, System};
use windows_sys::Win32::{
    Foundation::{ERROR_INVALID_PARAMETER, HWND, LPARAM, WAIT_OBJECT_0},
    System::Threading::*,
    UI::WindowsAndMessaging::*,
};

use super::{ProcessAction, image_identity};

fn open_process(pid: u32, extra_access: u32) -> std::io::Result<Option<OwnedHandle>> {
    let access = PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE | extra_access;
    let raw = unsafe { OpenProcess(access, 0, pid) };
    if !raw.is_null() {
        return Ok(Some(unsafe { OwnedHandle::from_raw_handle(raw) }));
    }
    let error = std::io::Error::last_os_error();
    if error.raw_os_error() == Some(ERROR_INVALID_PARAMETER as i32) {
        return Ok(None);
    }
    Err(error)
}

fn running_image(handle: BorrowedHandle<'_>) -> Result<Option<OsString>, String> {
    let raw = handle.as_raw_handle();
    if unsafe { WaitForSingleObject(raw, 0) } == WAIT_OBJECT_0 {
        return Ok(None);
    }
    let mut name = vec![0u16; 32768];
    let mut length = name.len() as u32;
    if unsafe {
        QueryFullProcessImageNameW(raw, PROCESS_NAME_WIN32, name.as_mut_ptr(), &mut length)
    } != 0
    {
        return Ok(Some(OsString::from_wide(&name[..length as usize])));
    }
    if unsafe { WaitForSingleObject(raw, 0) } == WAIT_OBJECT_0 {
        Ok(None)
    } else {
        Err("gameProcessUnknown".into())
    }
}

pub fn matching_pids(dir: &Path) -> Result<Vec<u32>, String> {
    let target = image_identity(&dir.join("Machine Party.exe")).map_err(|_| "invalidGame")?;
    let system = System::new_with_specifics(
        RefreshKind::nothing().with_processes(ProcessRefreshKind::nothing()),
    );
    let mut pids = Vec::new();
    for process in system.processes().values().filter(|p| {
        p.name()
            .eq_ignore_ascii_case(OsStr::new("Machine Party.exe"))
    }) {
        let pid = process.pid().as_u32();
        let Some(handle) = open_process(pid, 0).map_err(|_| "gameProcessUnknown")? else {
            continue;
        };
        let Some(path) = running_image(handle.as_handle())? else {
            continue;
        };
        if image_identity(Path::new(&path)).map_err(|_| "gameProcessUnknown")? == target {
            pids.push(pid);
        }
    }
    Ok(pids)
}

unsafe extern "system" fn close_window(hwnd: HWND, pid: LPARAM) -> i32 {
    visit_window(hwnd, pid as u32, |window| unsafe {
        PostMessageW(window, WM_CLOSE, 0, 0)
    })
}

fn visit_window(hwnd: HWND, pid: u32, post_close: impl FnOnce(HWND) -> i32) -> i32 {
    let mut owner = 0;
    unsafe {
        GetWindowThreadProcessId(hwnd, &mut owner);
        if owner == pid && IsWindowVisible(hwnd) != 0 && GetWindow(hwnd, GW_OWNER).is_null() {
            // Zero stops EnumWindows and propagates a failed delivery to the caller.
            return post_close(hwnd);
        }
    }
    1
}

fn check_action_result(ok: i32, handle: BorrowedHandle<'_>) -> Result<(), String> {
    if ok != 0 || unsafe { WaitForSingleObject(handle.as_raw_handle(), 0) } == WAIT_OBJECT_0 {
        Ok(())
    } else {
        Err("gameCloseFailed".into())
    }
}

pub fn apply(dir: &Path, action: ProcessAction) -> Result<bool, String> {
    let pids = matching_pids(dir)?;
    if matches!(action, ProcessAction::Check) || pids.is_empty() {
        return Ok(!pids.is_empty());
    }
    let target = image_identity(&dir.join("Machine Party.exe")).map_err(|_| "invalidGame")?;
    for pid in pids {
        let extra = if matches!(action, ProcessAction::Force) {
            PROCESS_TERMINATE
        } else {
            0
        };
        let Some(handle) = open_process(pid, extra).map_err(|_| "gameCloseFailed")? else {
            continue;
        };
        // Recheck the image on the pinned process before sending any close request.
        let Some(path) = running_image(handle.as_handle())? else {
            continue;
        };
        if image_identity(Path::new(&path)).map_err(|_| "gameProcessUnknown")? != target {
            continue;
        }
        let ok = unsafe {
            match action {
                ProcessAction::Close => EnumWindows(Some(close_window), pid as LPARAM),
                ProcessAction::Force => TerminateProcess(handle.as_raw_handle(), 1),
                ProcessAction::Check => unreachable!(),
            }
        };
        check_action_result(ok, handle.as_handle())?;
        if matches!(action, ProcessAction::Force) {
            // TerminateProcess is asynchronous. Defer to UI polling if exit is still pending.
            if unsafe { WaitForSingleObject(handle.as_raw_handle(), 1000) } != WAIT_OBJECT_0 {
                return Ok(true);
            }
        }
    }
    Ok(!matching_pids(dir)?.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::{Command, Stdio};

    #[test]
    fn failed_post_to_a_game_window_stops_enumeration() {
        use std::ptr::{null, null_mut};
        let window = unsafe {
            CreateWindowExW(
                0,
                windows_sys::core::w!("STATIC"),
                null(),
                WS_VISIBLE | WS_POPUP,
                0,
                0,
                1,
                1,
                null_mut(),
                null_mut(),
                null_mut(),
                null(),
            )
        };
        assert!(!window.is_null());
        let result = visit_window(window, std::process::id(), |_| 0);
        unsafe {
            DestroyWindow(window);
        }
        assert_eq!(result, 0);
    }

    #[test]
    fn rejected_close_is_an_error_only_while_the_target_is_alive() {
        let mut child = Command::new("cmd.exe")
            .args(["/D", "/Q", "/K"])
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .spawn()
            .unwrap();
        // EnumWindows returns zero when the callback stops on failed delivery.
        let live_result = check_action_result(0, child.as_handle());
        child.kill().unwrap();
        child.wait().unwrap();
        assert_eq!(live_result.unwrap_err(), "gameCloseFailed");
        check_action_result(0, child.as_handle()).unwrap();
        assert!(running_image(child.as_handle()).unwrap().is_none());
    }
}
