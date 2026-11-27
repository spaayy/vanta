//! Runs the Atlas front door (`Install-Vanta.ps1`) as a child process.
//!
//! The child writes to a log file rather than a pipe, so it never blocks on
//! this app and keeps running if the window is closed. A session record
//! (see [`super::session`]) names the process and the log, and a wrapper
//! command writes the script's exit code beside the log, so a reopened app
//! can pick the install up again and learn how it ended.

mod command;
mod follow;
#[cfg(test)]
mod tests;

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use futures::channel::mpsc::{Receiver, channel};
use serde::{Deserialize, Serialize};

use super::session::{self, Inspection, LaunchLock, SessionPaths, SessionRecord};
use super::{package, powershell, system};
#[cfg(test)]
pub(crate) use command::ps_quote;
use command::wrapper_command;
pub use command::{command_line, valid_option_name, validate_options};
pub use follow::machine_log_path;
use follow::{EVENT_BACKLOG, follow};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InstallRequest {
    /// The unpacked package to install. Records from earlier builds name it
    /// `playbookDir`.
    #[serde(alias = "playbookDir")]
    pub package_dir: PathBuf,
    pub options: Vec<String>,
    /// Restart Windows once the install succeeds. Atlas restarts it itself;
    /// the front door is never asked to.
    pub restart: bool,
    /// The user confirmed by hand, in Windows Security, the switches Atlas
    /// couldn't read, so the front door accepts those unread. One that reads
    /// on still stops it. Records from earlier builds lack it.
    #[serde(default)]
    pub windows_security_confirmed: bool,
    /// An update or reinstall goes through every choice again and applies
    /// each one (`-ChooseAgain`), rather than keeping them as the PC has
    /// them. Records from earlier builds lack it, and kept them.
    #[serde(default)]
    pub choose_again: bool,
}

#[derive(Clone, Debug)]
pub enum InstallEvent {
    /// A batch of output lines, oldest first.
    Lines(Vec<String>),
    /// Output could not be read; the install itself may still be running.
    /// Carries the raw I/O error as a diagnostic.
    OutputProblem(String),
    Finished(InstallOutcome),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstallOutcome {
    Succeeded,
    /// Exit code from the script: 1 failure, 2 requirements not met, 3 not
    /// elevated, 5 Windows or Store preparation is not current (see
    /// [`InstallOutcome::needs_preparation`]).
    Failed(i32),
    /// The wrapper never received the go-ahead (the install record could not
    /// be established), so the front door was not run.
    NotStarted,
    /// The process ended without reporting a result (found after reopening).
    Lost,
}

impl InstallOutcome {
    pub fn is_success(self) -> bool {
        matches!(self, InstallOutcome::Succeeded)
    }

    /// The front door's live check found Windows or Microsoft Store updates
    /// unfinished, so it stopped before installing; preparation runs again.
    pub fn needs_preparation(self) -> bool {
        self == InstallOutcome::Failed(PREPARATION_NOT_CURRENT_EXIT_CODE)
    }
}

/// How far the front door got, read from its own progress lines.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub enum Phase {
    /// Checks and staging preparation; nothing on the PC has changed.
    #[default]
    Preflight,
    /// Atlas's files are being copied to the protected staging directory and
    /// the install state captured; Windows itself is unchanged.
    Staging,
    /// The install plan is running as TrustedInstaller; changes are being applied.
    Applying,
    Done,
}

impl Phase {
    /// The phase a front door output line announces, if it announces one.
    pub fn from_line(line: &str) -> Option<Phase> {
        let line = line.trim_start();
        let text = line.strip_prefix("[Vanta]")?.trim_start();
        if text.starts_with("Copying Vanta's files") || text.starts_with("Capturing the install state") {
            Some(Phase::Staging)
        } else if text.starts_with("Running the install plan") {
            Some(Phase::Applying)
        } else if text.starts_with("Vanta installed successfully") {
            Some(Phase::Done)
        } else if text.starts_with("Staging the payload") {
            // The copy step as earlier 0.6.0 test packages word it. The app
            // runs whichever package is loaded, so it still reads this.
            Some(Phase::Staging)
        } else {
            None
        }
    }
}

/// Completed plan actions plus the final state commit, as the install
/// scripts report them.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PlanProgress {
    pub completed: u32,
    pub total: u32,
}

impl PlanProgress {
    pub fn from_line(line: &str) -> Option<Self> {
        let marker = "[VantaProgress] ";
        let text = line
            .strip_prefix(marker)
            .or_else(|| line.split_once("] [INFO] [VantaProgress] ").map(|(_, text)| text))?;
        let (completed, total) = text.trim().split_once('/')?;
        let completed = completed.parse().ok()?;
        let total = total.parse().ok()?;
        (total > 0 && completed <= total).then_some(Self { completed, total })
    }

    pub fn fraction(self) -> f32 {
        self.completed as f32 / self.total as f32
    }
}

/// The shared install record cannot be read, so no install may start.
#[derive(Debug)]
pub struct RecordUnreadable(pub String);

impl std::fmt::Display for RecordUnreadable {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "the record of the last install cannot be read ({}), so Atlas cannot tell whether it is still running; nothing was started",
            self.0
        )
    }
}

impl std::error::Error for RecordUnreadable {}

/// Another install is already running; the caller should follow it.
#[derive(Debug)]
pub struct AlreadyRunning(pub SessionRecord);

impl std::fmt::Display for AlreadyRunning {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "an install started at {} is still running (process {})", self.0.started_at, self.0.pid)
    }
}

impl std::error::Error for AlreadyRunning {}

/// [`start_as`] with a fresh id.
#[cfg(test)]
pub fn start(
    request: InstallRequest,
    paths: &SessionPaths,
) -> Result<(SessionRecord, Receiver<InstallEvent>)> {
    start_as(session::new_id(), request, paths)
}

/// Starts the installer as session `id` and records it. Output arrives on the
/// receiver, ending with `Finished`. The caller picks `id` so it can save it
/// (in its draft, say) before the install runs.
///
/// Launching and recording are one protocol, serialised across windows by
/// the launch lock: a running install is refused with [`AlreadyRunning`]; the
/// record is written before the child starts and rewritten with its process
/// identity; only then may the child run the front door. Any failure before
/// that leaves nothing running.
pub fn start_as(
    id: String,
    request: InstallRequest,
    paths: &SessionPaths,
) -> Result<(SessionRecord, Receiver<InstallEvent>)> {
    launch(id, request, paths, LaunchLock::WAIT)
}

/// [`start_as`], waiting at most `lock_wait` for another window's launch.
fn launch(
    id: String,
    request: InstallRequest,
    paths: &SessionPaths,
    lock_wait: Duration,
) -> Result<(SessionRecord, Receiver<InstallEvent>)> {
    let script = package::front_door(&request.package_dir);
    log::info!(
        "Installation session {id} requested; package={:?}; options={:?}",
        package::identity(&request.package_dir),
        request.options
    );
    anyhow::ensure!(script.is_file(), "{} is missing", script.display());
    validate_options(&request.options)?;

    let lock = LaunchLock::acquire_within(paths, lock_wait).context("nothing was started")?;
    match lock.inspect(paths) {
        Inspection::Live(existing) => return Err(AlreadyRunning(existing).into()),
        Inspection::Unreadable(problem) => return Err(RecordUnreadable(problem).into()),
        Inspection::None | Inspection::Ended(_) | Inspection::Abandoned => {}
    }

    fs::create_dir_all(&paths.logs).with_context(|| format!("create {}", paths.logs.display()))?;
    let mut record = SessionRecord {
        pid: 0,
        process_start: 0,
        started_at: chrono::Local::now().to_rfc3339(),
        log_path: paths.logs.join(format!("install-{id}.log")),
        exit_path: paths.logs.join(format!("install-{id}.exit")),
        id,
        request,
    };
    // The elevated install runs from a copy no other process can touch, not
    // from the user's profile (see [`trusted_stage`]).
    let staged = trusted_stage(&record.request)?;
    let run_request = staged.as_ref().map(|dir| InstallRequest { package_dir: dir.clone(), ..record.request.clone() });
    let run_request = run_request.as_ref().unwrap_or(&record.request);
    let command =
        wrapper_command(run_request, &record.exit_path, &record.go_path(), HANDOVER_TIMEOUT_SECONDS)?;
    let log = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&record.log_path)
        .with_context(|| format!("create {}", record.log_path.display()))?;
    let (log, log_err) = match record_launch(paths, &record, log) {
        Ok(log) => log,
        Err(error) => {
            remove_artifacts(&record);
            return Err(error.context("record the install before starting it; nothing was started"));
        }
    };

    let drop_stage = |staged: &Option<PathBuf>| {
        if let Some(dir) = staged {
            package::remove_stage(dir);
        }
    };
    let spawned = powershell::command()
        .arg("-Command")
        .arg(&command)
        .current_dir(&run_request.package_dir)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(log_err))
        .spawn();
    let mut child = match spawned {
        Ok(child) => child,
        Err(error) => {
            lock.discard(paths);
            remove_artifacts(&record);
            drop_stage(&staged);
            return Err(anyhow::Error::from(error).context("start Windows PowerShell; nothing was started"));
        }
    };
    #[cfg(test)]
    LAST_SPAWNED.with(|last| last.set((child.id(), system::process_start_time(child.id()).unwrap_or(0))));

    if let Err(error) = hand_over(paths, &mut record, &child, staged.as_deref()) {
        let _ = child.kill();
        let _ = child.wait();
        lock.discard(paths);
        remove_artifacts(&record);
        drop_stage(&staged);
        return Err(error.context("record the install before starting it; nothing was started"));
    }
    if let Some(dir) = staged {
        keep_stage_until_done(dir, &record);
    }

    let (sender, receiver) = channel(EVENT_BACKLOG);
    let (log_path, offset_path) = (record.log_path.clone(), record.machine_offset_path());
    let machine_log = paths.machine_log.clone();
    thread::spawn(move || follow(log_path, offset_path, machine_log, Watch::Owned(child), sender));
    Ok((record, receiver))
}

/// Only SYSTEM and Administrators may touch the directory the install runs from.
const STAGE_SDDL: &str = "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)";

/// In an embedded build, unpacks the archive compiled into this executable (the
/// only bytes whose digest nothing in the user's profile can change) into a new
/// protected directory under `%ProgramData%` and returns it; the install runs
/// from there. Another build has no such trusted archive and runs the unpacked
/// copy it was given. The directory the request names must hold that same
/// archive, or the install is refused.
fn trusted_stage(request: &InstallRequest) -> Result<Option<PathBuf>> {
    // The unit tests install throw-away packages, never the compiled-in one; `package::tests` covers the staging itself.
    if cfg!(test) {
        return Ok(None);
    }
    let Some((bytes, digest)) = super::embedded::trusted_package() else { return Ok(None) };
    anyhow::ensure!(
        package::identity(&request.package_dir).is_some_and(|identity| identity.sha256.eq_ignore_ascii_case(digest)),
        "{} does not hold the package built into this app; nothing was started",
        request.package_dir.display()
    );
    let parent = PathBuf::from(std::env::var_os("ProgramData").context("ProgramData is not set")?);
    // Recovery of leftovers: only stages that prove they are the Vanta's and whose processes are gone.
    package::sweep_stages(
        &parent,
        |owner| system::process_liveness_global(owner.pid, owner.start),
        super::files::is_protected_vanta_dir,
    );
    let me = package::StageOwner {
        pid: std::process::id(),
        start: system::process_start_time(std::process::id()).context("read this process's start time")?,
    };
    package::stage_protected(bytes, digest, &parent, STAGE_SDDL, &[me]).map(Some).context("stage the package for the install")
}

/// The staged copy lives exactly as long as the install it serves (see
/// [`hand_over`], which records the install process on it first) and is removed,
/// and only this directory, once that process has confirmed ended.
fn keep_stage_until_done(dir: PathBuf, record: &SessionRecord) {
    let install = package::StageOwner { pid: record.pid, start: record.process_start };
    thread::spawn(move || {
        // Only a confirmed end releases it; "cannot tell" keeps waiting, and a Manager that exits first leaves
        // the stage for a later recovery, which also waits for every process the marker names.
        while system::process_liveness_global(install.pid, install.start) != system::Liveness::Ended {
            thread::sleep(Duration::from_secs(5));
        }
        package::remove_stage(&dir);
    });
}

/// Notes where the machine log stands and writes the record, which must be
/// on disk before anything runs. Returns the log twice, for the child's
/// output and its errors.
fn record_launch(
    paths: &SessionPaths,
    record: &SessionRecord,
    log: fs::File,
) -> Result<(fs::File, fs::File)> {
    // Every install appends to the machine log; remember where this one
    // starts so a follower shows only its lines.
    let machine_offset = fs::metadata(&paths.machine_log).map(|m| m.len()).unwrap_or(0);
    fs::write(record.machine_offset_path(), machine_offset.to_string())?;
    let log_err = log.try_clone().context("share the log file")?;
    fail_point(FailPoint::InitialRecord)?;
    session::save(paths, record)?;
    Ok((log, log_err))
}

/// Records the waiting child as the install's process, then gives it the
/// go-ahead. A start time that cannot be read is a failure too: without it a
/// later process that reuses the PID would pass for the installer.
fn hand_over(paths: &SessionPaths, record: &mut SessionRecord, child: &Child, staged: Option<&Path>) -> Result<()> {
    record.pid = child.id();
    record.process_start =
        system::process_start_time(child.id()).context("read the installer process's start time")?;
    fail_point(FailPoint::RecordRewrite)?;
    session::save(paths, record)?;
    // The staged copy must name the install before the install may run from it: if this cannot be written, nothing starts.
    if let Some(dir) = staged {
        let me = package::StageOwner {
            pid: std::process::id(),
            start: system::process_start_time(std::process::id()).context("read this process's start time")?,
        };
        package::set_stage_owners(dir, &[me, package::StageOwner { pid: record.pid, start: record.process_start }])
            .context("record the install on its staged package")?;
    }
    fail_point(FailPoint::GoAhead)?;
    let go = record.go_path();
    fs::write(&go, "go").with_context(|| format!("write {}", go.display()))
}

/// Removes what a launch that never ran the front door left in the logs.
fn remove_artifacts(record: &SessionRecord) {
    let _ = fs::remove_file(&record.log_path);
    let _ = fs::remove_file(record.machine_offset_path());
}

/// Points in the launch protocol where a test can inject a failure.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FailPoint {
    InitialRecord,
    RecordRewrite,
    GoAhead,
}

#[cfg(test)]
thread_local! {
    static FAIL_AT: std::cell::Cell<Option<FailPoint>> = const { std::cell::Cell::new(None) };
    /// The last child spawned on this thread and its creation time, so a
    /// test can tell it apart from a later process given the same PID.
    static LAST_SPAWNED: std::cell::Cell<(u32, u64)> = const { std::cell::Cell::new((0, 0)) };
}

#[cfg(test)]
fn fail_point(point: FailPoint) -> Result<()> {
    if FAIL_AT.with(|fail| fail.get()) == Some(point) {
        anyhow::bail!("injected failure at {point:?}");
    }
    Ok(())
}

#[cfg(not(test))]
fn fail_point(_point: FailPoint) -> Result<()> {
    Ok(())
}

/// Follows an install that an earlier app instance started, with the machine
/// log at `machine_log` (see [`SessionPaths::machine_log`]). Output starts
/// from the beginning of the log, so the whole history is available.
pub fn reattach(record: &SessionRecord, machine_log: &Path) -> Receiver<InstallEvent> {
    let (sender, receiver) = channel(EVENT_BACKLOG);
    let (log_path, offset_path) = (record.log_path.clone(), record.machine_offset_path());
    let (machine_log, watch) = (machine_log.to_path_buf(), Watch::Detached(record.clone()));
    thread::spawn(move || follow(log_path, offset_path, machine_log, watch, sender));
    receiver
}

enum Watch {
    Owned(Child),
    Detached(SessionRecord),
}

impl Watch {
    /// `Some(outcome)` once the installer has ended.
    fn poll(&mut self) -> Option<InstallOutcome> {
        match self {
            Watch::Owned(child) => match child.try_wait() {
                Ok(Some(status)) => Some(outcome_from_code(status.code())),
                Ok(None) => None,
                Err(_) => Some(InstallOutcome::Lost),
            },
            Watch::Detached(record) => {
                if let Some(code) = record.exit_code() {
                    return Some(outcome_from_code(Some(code)));
                }
                if record.is_alive() {
                    return None;
                }
                // The process is gone; give a just-written exit file a moment.
                let deadline = Instant::now() + Duration::from_secs(2);
                while Instant::now() < deadline {
                    if let Some(code) = record.exit_code() {
                        return Some(outcome_from_code(Some(code)));
                    }
                    thread::sleep(Duration::from_millis(100));
                }
                Some(ended_without_a_result(record))
            }
        }
    }
}

/// An install whose process ended without writing its exit code. Without
/// its go-ahead file the wrapper never ran the front door (the window died,
/// or Windows restarted, during the handoff), so nothing was started; with
/// it, or with no log left to say so, the result is unknown.
fn ended_without_a_result(record: &SessionRecord) -> InstallOutcome {
    if record.log_path.is_file() && !record.go_path().exists() {
        InstallOutcome::NotStarted
    } else {
        InstallOutcome::Lost
    }
}

/// Exit code the wrapper uses when the go-ahead never arrived. The front
/// door's own codes are 0 to 3 and 5.
const NOT_STARTED_EXIT_CODE: i32 = 4;
/// Exit code the front door uses when Windows or Store preparation is not current.
const PREPARATION_NOT_CURRENT_EXIT_CODE: i32 = 5;
/// How long the wrapper waits for the go-ahead before giving up.
const HANDOVER_TIMEOUT_SECONDS: u32 = 60;

fn outcome_from_code(code: Option<i32>) -> InstallOutcome {
    match code {
        Some(0) => InstallOutcome::Succeeded,
        Some(NOT_STARTED_EXIT_CODE) => InstallOutcome::NotStarted,
        Some(code) => InstallOutcome::Failed(code),
        None => InstallOutcome::Lost,
    }
}
