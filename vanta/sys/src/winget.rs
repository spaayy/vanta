//! `CommandRunner` real: roda o winget (ou qualquer exe) sem janela e devolve código e saída.

use std::io;
use std::os::windows::process::CommandExt;
use std::process::Command;

use vanta_core::install::{CommandResult, CommandRunner};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

pub struct WingetRunner;

impl CommandRunner for WingetRunner {
    fn run(&self, executable: &str, arguments: &[String]) -> io::Result<CommandResult> {
        let output = Command::new(executable).args(arguments).creation_flags(CREATE_NO_WINDOW).output()?;
        Ok(CommandResult {
            exit_code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn returns_the_exit_code_and_the_output() {
        let runner = WingetRunner;
        let result = runner.run("cmd.exe", &["/c".into(), "echo oi & exit 3".into()]).unwrap();
        assert_eq!(result.exit_code, 3);
        assert!(result.stdout.contains("oi"));
    }

    #[test]
    fn a_missing_program_is_an_error_not_a_panic() {
        assert!(WingetRunner.run("vanta-nao-existe.exe", &[]).is_err());
    }
}
