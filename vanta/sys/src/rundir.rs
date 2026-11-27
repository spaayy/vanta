//! Pasta de execução do lado elevado: `%ProgramData%\Vanta\run\<guid>`, criada pelo LADO ELEVADO (nunca pelo usuário).
//!
//! O que o lado elevado garante, na ordem, antes de escrever qualquer coisa:
//! 1. A base (`%ProgramData%`) é aberta por HANDLE sem seguir link: sem ponto de reanálise e com dono SYSTEM,
//!    TrustedInstaller ou Administradores. O handle fica aberto sem compartilhar exclusão.
//! 2. `Vanta` e `Vanta\run`: se já existem, abertas do mesmo jeito; o DONO e a ACL são lidos PELO PRÓPRIO HANDLE
//!    (`GetKernelObjectSecurity`), não pelo caminho: nenhum outro principal pode ter escrita, apagar ou mudar
//!    permissões. Um usuário comum pode criar `C:\ProgramData\Vanta`: a pasta dele não passa. Se não existem, são CRIADAS
//!    já com a ACL (`Directory.CreateDirectory(caminho, ACL)`: não há instante sem ACL) e conferidas do mesmo jeito.
//! 3. `<guid>`: criada com ACL (Administradores e SYSTEM, controle total; o usuário interativo só leitura), tem de estar
//!    vazia, recebe a marca `.vanta-run` e o arquivo-sinal de cancelamento.
//! 4. O sinal tem tamanho FIXO (8 bytes) e o usuário tem só o direito de escrever dados nele; o lado elevado o abre uma
//!    vez (handle) e lê sempre os mesmos 8 bytes por esse handle.
//! 5. A limpeza só apaga pastas com nome de GUID, sem ponto de reanálise, com a marca do Vanta cujo conteúdo é o
//!    próprio nome, com mais de um dia E que passam na mesma conferência de dono e ACL.

use std::path::{Path, PathBuf};

/// Um GUID no formato 8-4-4-4-12 em hexadecimal (o id da execução; nada de caminho vindo de fora).
pub fn is_run_id(id: &str) -> bool {
    let parts: Vec<&str> = id.split('-').collect();
    parts.len() == 5
        && parts
            .iter()
            .zip([8, 4, 4, 4, 12])
            .all(|(p, n)| p.len() == n && p.chars().all(|c| c.is_ascii_hexdigit()))
}

/// SID de usuário local/de domínio (`S-1-5-21-...`).
pub fn is_user_sid(sid: &str) -> bool {
    sid.strip_prefix("S-1-5-21-")
        .is_some_and(|rest| !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit() || c == '-'))
}

/// O caminho da pasta de execução (o mesmo que o script calcula com `$env:ProgramData`).
pub fn run_dir(program_data: &str, run_id: &str) -> PathBuf {
    PathBuf::from(program_data).join("Vanta").join("run").join(run_id)
}

/// Nome do arquivo-marca que o Vanta grava em toda pasta de execução que cria.
pub const RUN_MARKER: &str = ".vanta-run";

/// Conteúdo da marca: o próprio id, em minúsculas.
pub fn run_marker_text(run_id: &str) -> String {
    format!("vanta-run:{}", run_id.to_lowercase())
}

/// O sinal de cancelamento: exatamente estes 8 bytes. Antes do pedido o arquivo tem 8 bytes zero.
pub const CANCEL_WORD: &[u8; 8] = b"cancelar";

/// Escreve o sinal NO arquivo que o lado elevado criou (nada é criado aqui): abre só com o direito de escrever dados,
/// sem truncar, e grava as 8 letras no começo. Sem o arquivo, não faz nada.
pub fn signal_cancel(signal: &Path) {
    use std::io::Write;
    use std::os::windows::fs::OpenOptionsExt;
    const FILE_WRITE_DATA: u32 = 0x0002;
    const SYNCHRONIZE: u32 = 0x0010_0000;
    if let Ok(mut file) =
        std::fs::OpenOptions::new().write(true).access_mode(FILE_WRITE_DATA | SYNCHRONIZE).open(signal)
    {
        let _ = file.write_all(CANCEL_WORD);
    }
}

/// Funções PowerShell do lado elevado (compatíveis com o Windows PowerShell 5.1). `New-VantaRunDir` faz tudo acima;
/// `New-VantaRunAcl` só monta a ACL e `Remove-VantaStaleRuns` só limpa (ambas testáveis sem administrador).
/// Sem here-string aqui dentro: o texto é embutido em outros scripts.
pub const RUN_DIR_PS: &str = r#"$script:VantaTrustedSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$script:VantaGuidRegex = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'
$script:VantaRunHandles = @()
$script:VantaCancelStream = $null
$script:VantaTestWriters = @()   # só os testes preenchem (sem administrador); a produção nunca
if (-not ('VantaNative' -as [type])) {
    Add-Type -TypeDefinition ((@(
        'using System;',
        'using System.Runtime.InteropServices;',
        'using Microsoft.Win32.SafeHandles;',
        'public static class VantaNative {',
        '  [StructLayout(LayoutKind.Sequential)]',
        '  public struct FileInfo { public uint Attributes; public long Created; public long Accessed; public long Written; public uint Volume; public uint SizeHigh; public uint SizeLow; public uint Links; public uint IndexHigh; public uint IndexLow; }',
        '  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]',
        '  public static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);',
        '  [DllImport("kernel32.dll", SetLastError = true)]',
        '  public static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);',
        '  [DllImport("advapi32.dll", SetLastError = true)]',
        '  public static extern bool GetKernelObjectSecurity(SafeFileHandle handle, uint requested, byte[] descriptor, uint length, out uint needed);',
        '}') -join [Environment]::NewLine))
}
function New-VantaRunAcl {
    param([Parameter(Mandatory = $true)][string]$UserSid, [ValidateSet('Dir', 'CancelFile')][string]$Kind = 'Dir')
    $acl = if ($Kind -eq 'Dir') { New-Object Security.AccessControl.DirectorySecurity } else { New-Object Security.AccessControl.FileSecurity }
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = if ($Kind -eq 'Dir') { [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' } else { [Security.AccessControl.InheritanceFlags]::None }
    $none = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    foreach ($admin in (@('S-1-5-32-544', 'S-1-5-18') + @($script:VantaTestWriters))) {
        $sid = New-Object Security.Principal.SecurityIdentifier $admin
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', $inherit, $none, $allow)))
    }
    $user = New-Object Security.Principal.SecurityIdentifier $UserSid
    # no sinal o usuário só escreve dados (e sincroniza o handle): sem anexar, sem atributos, sem apagar, sem permissões
    $rights = if ($Kind -eq 'Dir') { 'ReadAndExecute' } else { 'WriteData, Synchronize' }
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($user, $rights, $inherit, $none, $allow)))
    return $acl
}
function Open-VantaDirHandle {
    <# Abre a pasta sem seguir link; recusa ponto de reanálise (pelo atributo do PRÓPRIO handle). Com -Hold o handle fica
       aberto até o fim do processo e sem compartilhar exclusão; sem -Hold compartilha tudo e quem chama o fecha. #>
    param([Parameter(Mandatory = $true)][string]$Path, [switch]$Hold)
    # FILE_READ_ATTRIBUTES | READ_CONTROL; FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT
    $share = if ($Hold) { 3 } else { 7 }
    $handle = [VantaNative]::CreateFileW($Path, 0x20080, $share, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
    if ($handle.IsInvalid) { throw "não foi possível abrir sem seguir links: $Path" }
    $info = New-Object VantaNative+FileInfo
    if (-not [VantaNative]::GetFileInformationByHandle($handle, [ref]$info)) { $handle.Dispose(); throw "não foi possível ler os atributos de $Path" }
    if (($info.Attributes -band 0x400) -ne 0) { $handle.Dispose(); throw "ponto de reanálise recusado: $Path" }
    if (($info.Attributes -band 0x10) -eq 0) { $handle.Dispose(); throw "não é uma pasta: $Path" }
    if ($Hold) { $script:VantaRunHandles += $handle }
    return $handle
}
function Get-VantaHandleSecurity {
    <# Dono e DACL lidos PELO HANDLE (o mesmo objeto que foi aberto e conferido), não por um caminho. #>
    param([Parameter(Mandatory = $true)]$Handle)
    $needed = [uint32]0
    [void][VantaNative]::GetKernelObjectSecurity($Handle, 5, $null, 0, [ref]$needed)
    if ($needed -eq 0) { throw 'não foi possível medir as permissões pelo handle' }
    $buffer = New-Object byte[] $needed
    if (-not [VantaNative]::GetKernelObjectSecurity($Handle, 5, $buffer, $needed, [ref]$needed)) { throw 'não foi possível ler as permissões pelo handle' }
    return (New-Object Security.AccessControl.RawSecurityDescriptor($buffer, 0))
}
function Assert-VantaTrustedHandle {
    param([Parameter(Mandatory = $true)]$Handle, [Parameter(Mandatory = $true)][string]$Path, [string[]]$TrustedOwners = $script:VantaTrustedSids, [switch]$OwnerOnly)
    $descriptor = Get-VantaHandleSecurity -Handle $Handle
    $owner = [string]$descriptor.Owner.Value
    if ($owner -cnotin $TrustedOwners) { throw "dono não confiável ($owner): $Path" }
    if ($OwnerOnly) { return }
    if ($null -eq $descriptor.DiscretionaryAcl) { throw "sem ACL (todos escrevem): $Path" }
    # escrever, criar, apagar, mudar permissões ou tomar posse: só SYSTEM, TrustedInstaller e Administradores
    $mask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000   # inclui GENERIC_ALL e GENERIC_WRITE
    foreach ($ace in $descriptor.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.CommonAce]) { continue }
        if ([int]$ace.AceQualifier -ne 0) { continue }   # só AccessAllowed
        if (([int]$ace.AceFlags -band 8) -ne 0) { continue }   # InheritOnly: não vale para este objeto
        $who = [string]$ace.SecurityIdentifier.Value
        if ($who -cin $script:VantaTrustedSids -or $who -cin $script:VantaTestWriters) { continue }
        if (($ace.AccessMask -band $mask) -ne 0) { throw "permissão de escrita para $who em $Path" }
    }
}
function Assert-VantaTrustedDir {
    <# Confere uma pasta que não será mantida aberta (a limpeza): abre, lê dono e ACL pelo handle e fecha. #>
    param([Parameter(Mandatory = $true)][string]$Path, [string[]]$TrustedOwners = $script:VantaTrustedSids)
    $handle = Open-VantaDirHandle -Path $Path
    try { Assert-VantaTrustedHandle -Handle $handle -Path $Path -TrustedOwners $TrustedOwners } finally { $handle.Dispose() }
}
function Use-VantaProtectedDir {
    <# Pasta onde só administradores escrevem (C:\Vanta, C:\Vanta\System): criada já com a ACL, ou, se existe, aceita só com dono
       confiável e sem ponto de reanálise (pelo handle) e então APERTADA (um pai antigo com ACL frouxa herdada de C:\ não serve).
       Depois do aperto, dono e ACL são conferidos de novo, ainda pelo mesmo handle. #>
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$UserSid, [string[]]$TrustedOwners = $script:VantaTrustedSids)
    $existed = Test-Path -LiteralPath $Path
    if (-not $existed) { $null = [IO.Directory]::CreateDirectory($Path, (New-VantaRunAcl -UserSid $UserSid -Kind Dir)) }
    $handle = Open-VantaDirHandle -Path $Path -Hold
    Assert-VantaTrustedHandle -Handle $handle -Path $Path -TrustedOwners $TrustedOwners -OwnerOnly
    if ($existed) { [IO.Directory]::SetAccessControl($Path, (New-VantaRunAcl -UserSid $UserSid -Kind Dir)) }
    Assert-VantaTrustedHandle -Handle $handle -Path $Path -TrustedOwners $TrustedOwners
}
function Use-VantaTrustedDir {
    <# Abre (cria com ACL, se faltar), segura o handle e confere dono e ACL por ele, de uma pasta da cadeia. #>
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$UserSid, [string[]]$TrustedOwners = $script:VantaTrustedSids)
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = [IO.Directory]::CreateDirectory($Path, (New-VantaRunAcl -UserSid $UserSid -Kind Dir))
    }
    $handle = Open-VantaDirHandle -Path $Path -Hold
    Assert-VantaTrustedHandle -Handle $handle -Path $Path -TrustedOwners $TrustedOwners
}
function Open-VantaCancelStream {
    <# O sinal tem 8 bytes fixos: abre UMA vez (leitura, aceitando que o usuário escreva) e lê sempre pelo mesmo handle. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $script:VantaCancelStream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
}
function Test-VantaCancelled {
    if ($null -eq $script:VantaCancelStream) { return $false }
    $buffer = New-Object byte[] 8
    $null = $script:VantaCancelStream.Seek(0, [IO.SeekOrigin]::Begin)
    $read = $script:VantaCancelStream.Read($buffer, 0, 8)
    return ($read -eq 8 -and [Text.Encoding]::ASCII.GetString($buffer) -ceq 'cancelar')
}
function Remove-VantaStaleRuns {
    <# Só pastas de execução do próprio Vanta: nome de GUID, sem ponto de reanálise, marca .vanta-run com o próprio nome,
       mais velhas que $Days e que passam na conferência de dono e ACL. Nunca a pasta de $Keep. #>
    param([Parameter(Mandatory = $true)][string]$Run, [string]$Keep = '', [int]$Days = 1, [string[]]$TrustedOwners = $script:VantaTrustedSids)
    $limit = (Get-Date).AddDays(-$Days)
    foreach ($entry in @(Get-ChildItem -LiteralPath $Run -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($entry.Name -notmatch $script:VantaGuidRegex -or $entry.Name -ieq $Keep) { continue }
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        $marker = Join-Path $entry.FullName '.vanta-run'
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) { continue }
        $item = Get-Item -LiteralPath $marker -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.Length -gt 100) { continue }
        if (([IO.File]::ReadAllText($marker)).Trim() -cne ('vanta-run:' + $entry.Name.ToLowerInvariant())) { continue }
        if ($item.LastWriteTime -ge $limit) { continue }
        # uma marca é fácil de reproduzir: a pasta só sai se o dono e a ACL também são do Vanta (lidos pelo handle)
        try { Assert-VantaTrustedDir -Path $entry.FullName -TrustedOwners $TrustedOwners } catch { continue }
        try { [IO.Directory]::Delete($entry.FullName, $true) } catch { }
    }
}
function New-VantaRunDir {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Guid,
        [Parameter(Mandatory = $true)][string]$UserSid,
        [string[]]$TrustedOwners = $script:VantaTrustedSids,
        [string[]]$TestWriters = @()
    )
    $script:VantaTestWriters = @($TestWriters)
    if ($Guid -notmatch $script:VantaGuidRegex) { throw 'id de execução inválido' }
    if ($UserSid -notmatch '^S-1-5-21-[\d-]+$') { throw 'SID do usuário inválido' }
    $vanta = Join-Path $Base 'Vanta'; $run = Join-Path $vanta 'run'; $dir = Join-Path $run $Guid
    # a base fica presa (handle sem compartilhar exclusão) e o dono dela é lido pelo handle; quem escreve na base é problema
    # do Windows (ProgramData deixa usuários criarem pastas): por isso o primeiro objeto conferido de verdade é \Vanta
    $baseHandle = Open-VantaDirHandle -Path $Base -Hold
    Assert-VantaTrustedHandle -Handle $baseHandle -Path $Base -TrustedOwners $TrustedOwners -OwnerOnly
    Use-VantaTrustedDir -Path $vanta -UserSid $UserSid -TrustedOwners $TrustedOwners
    Use-VantaTrustedDir -Path $run -UserSid $UserSid -TrustedOwners $TrustedOwners
    if (Test-Path -LiteralPath $dir) { throw "a pasta de execução já existe: $dir" }
    $null = [IO.Directory]::CreateDirectory($dir, (New-VantaRunAcl -UserSid $UserSid -Kind Dir))
    $dirHandle = Open-VantaDirHandle -Path $dir -Hold
    Assert-VantaTrustedHandle -Handle $dirHandle -Path $dir -TrustedOwners $TrustedOwners
    if ([IO.Directory]::GetFileSystemEntries($dir).Count -ne 0) { throw "a pasta de execução não estava vazia: $dir" }
    [IO.File]::WriteAllText((Join-Path $dir '.vanta-run'), ('vanta-run:' + $Guid.ToLowerInvariant()))
    $signal = Join-Path $dir 'cancelar.sinal'
    [IO.File]::WriteAllBytes($signal, (New-Object byte[] 8))
    [IO.File]::SetAccessControl($signal, (New-VantaRunAcl -UserSid $UserSid -Kind CancelFile))
    Open-VantaCancelStream -Path $signal
    Remove-VantaStaleRuns -Run $run -Keep $Guid -TrustedOwners $TrustedOwners
    return $dir
}
"#;

#[cfg(test)]
mod tests {
    use std::fs;
    use std::process::Command;

    use super::*;

    fn powershell(script: &str) -> (bool, String) {
        let out = Command::new("powershell.exe")
            // The child writes in the console's OEM code page (CP850 here); the tests read UTF-8, so say so.
            .args(["-NoProfile", "-NonInteractive", "-Command", &format!("[Console]::OutputEncoding=[Text.Encoding]::UTF8;{script}")])
            .output()
            .unwrap();
        (
            out.status.success(),
            format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr)),
        )
    }

    const USER: &str = "S-1-5-21-111-222-333-1001";
    const GUID: &str = "0f8fad5b-d9cb-469f-a165-70867728950e";

    /// SID do dono de uma pasta de teste (o usuário que roda os testes, ou Administradores se elevado).
    fn owner_of(path: &Path) -> String {
        let (_, out) = powershell(&format!(
            "([IO.Directory]::GetAccessControl('{}')).GetOwner([Security.Principal.SecurityIdentifier]).Value",
            path.display()
        ));
        out.trim().to_owned()
    }

    /// O usuário real que roda o teste: a pasta criada o inclui (leitura), então o teste consegue abri-la.
    fn real_sid() -> String {
        crate::restore_batch::current_sid().expect("SID do usuário atual")
    }

    fn make_run(base: &Path, guid: &str, trusted: &str) -> (bool, String) {
        make_run_with(base, guid, trusted, "")
    }

    /// `writers`: só nos testes (sem administrador), quem também ganha controle total e é aceito como escritor.
    fn make_run_with(base: &Path, guid: &str, trusted: &str, writers: &str) -> (bool, String) {
        powershell(&format!(
            "{RUN_DIR_PS}\ntry {{ $d = New-VantaRunDir -Base '{}' -Guid '{guid}' -UserSid '{}' -TrustedOwners @({trusted}) -TestWriters @({writers}); 'FEITO: ' + $d }} catch {{ 'RECUSADO: ' + $_.Exception.Message }}",
            base.display(),
            real_sid()
        ))
    }

    #[test]
    fn run_ids_and_sids_are_validated_and_the_path_is_under_programdata() {
        assert!(
            is_run_id(GUID)
                && !is_run_id("..\\x")
                && !is_run_id("0f8fad5b-d9cb-469f-a165")
                && !is_run_id(&format!("{GUID}x"))
        );
        assert!(
            is_user_sid(USER)
                && !is_user_sid("S-1-5-18")
                && !is_user_sid("S-1-5-21-")
                && !is_user_sid("S-1-5-21-1;calc")
        );
        assert_eq!(
            run_dir(r"C:\ProgramData", GUID),
            PathBuf::from(format!(r"C:\ProgramData\Vanta\run\{GUID}"))
        );
        assert_eq!(run_marker_text("0F8FAD5B-D9CB-469F-A165-70867728950E"), format!("vanta-run:{GUID}"));
    }

    #[test]
    fn the_run_dir_script_is_valid_powershell_and_has_no_here_string() {
        assert!(
            !RUN_DIR_PS.contains("@'") && !RUN_DIR_PS.contains("'@"),
            "o texto é embutido em outros scripts"
        );
        let script = format!(
            "$e=$null; [void][System.Management.Automation.Language.Parser]::ParseInput(@'\n{RUN_DIR_PS}\n'@, [ref]$null, [ref]$e); if ($e) {{ $e[0].Message; exit 1 }}"
        );
        let (ok, out) = powershell(&script);
        assert!(ok, "{out}");
    }

    #[test]
    fn owner_and_acl_are_read_from_the_handle_not_from_the_path() {
        // o script não consulta dono/ACL por caminho em lugar nenhum
        for forbidden in ["Get-Acl", "GetAccessControl($Path", "Set-Acl"] {
            assert!(!RUN_DIR_PS.contains(forbidden), "{forbidden}");
        }
        assert!(
            RUN_DIR_PS.contains("GetKernelObjectSecurity") && RUN_DIR_PS.contains("Get-VantaHandleSecurity")
        );
        // e funciona: o handle de uma pasta de teste devolve o dono dela
        let dir = tempfile::tempdir().unwrap();
        let (ok, out) = powershell(&format!(
            "{RUN_DIR_PS}\n$h = Open-VantaDirHandle -Path '{}'; (Get-VantaHandleSecurity -Handle $h).Owner.Value; $h.Dispose()",
            dir.path().display()
        ));
        assert!(ok, "{out}");
        assert_eq!(out.trim(), owner_of(dir.path()), "{out}");
    }

    #[test]
    fn the_acl_gives_admins_and_system_full_control_and_the_user_read_only_and_only_write_data_on_the_signal()
    {
        let script = format!(
            "{RUN_DIR_PS}\n$a = New-VantaRunAcl -UserSid '{USER}' -Kind Dir\n\
             'protected=' + $a.AreAccessRulesProtected\n\
             $a.Access | ForEach-Object {{ $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value + '|' + $_.FileSystemRights + '|' + $_.InheritanceFlags }}\n\
             $f = New-VantaRunAcl -UserSid '{USER}' -Kind CancelFile\n\
             $f.Access | ForEach-Object {{ 'FILE|' + $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value + '|' + [int]$_.FileSystemRights }}"
        );
        let (ok, out) = powershell(&script);
        assert!(ok, "{out}");
        assert!(out.contains("protected=True"), "{out}");
        assert!(out.contains("S-1-5-32-544|FullControl|ContainerInherit, ObjectInherit"), "{out}");
        assert!(out.contains("S-1-5-18|FullControl|ContainerInherit, ObjectInherit"), "{out}");
        assert!(
            out.contains(&format!("{USER}|ReadAndExecute, Synchronize|ContainerInherit, ObjectInherit")),
            "{out}"
        );
        let dir_lines: Vec<&str> = out.lines().filter(|l| !l.starts_with("FILE|")).collect();
        let dir_user = dir_lines.iter().find(|l| l.starts_with(USER)).expect("regra do usuário na pasta");
        assert!(
            !dir_user.contains("Write") && !dir_user.contains("Modify") && !dir_user.contains("Delete"),
            "{dir_user}"
        );
        // no sinal: só WriteData (+ Synchronize); sem anexar, sem atributos, sem ler, sem apagar
        let file_line =
            out.lines().find(|l| l.starts_with(&format!("FILE|{USER}"))).expect("regra do usuário no sinal");
        // 0x100002 = WriteData (0x2) + Synchronize (0x100000), e mais nada
        assert_eq!(file_line, format!("FILE|{USER}|{}", 0x0010_0002), "{file_line}");
    }

    #[test]
    fn the_cancel_signal_is_eight_fixed_bytes_read_through_one_handle() {
        let dir = tempfile::tempdir().unwrap();
        let signal = dir.path().join("cancelar.sinal");
        std::fs::write(&signal, [0u8; 8]).unwrap();
        // o usuário escreve só as 8 letras, sem criar nem truncar
        let missing = dir.path().join("nao-existe.sinal");
        signal_cancel(&missing);
        assert!(!missing.exists(), "nada é criado pelo lado do usuário");
        let (ok, out) = powershell(&format!(
            "{RUN_DIR_PS}\nOpen-VantaCancelStream -Path '{p}'\n'antes=' + (Test-VantaCancelled)\n",
            p = signal.display()
        ));
        assert!(ok && out.contains("antes=False"), "{out}");
        // com o handle do lado elevado aberto, o usuário grava e o próximo teste vê
        let script = format!(
            "{RUN_DIR_PS}\nOpen-VantaCancelStream -Path '{p}'\n'antes=' + (Test-VantaCancelled)\n[IO.File]::WriteAllBytes('{p}.cmd', [byte[]](0))\n",
            p = signal.display()
        );
        let _ = script; // o handle vive só dentro de um processo: o teste seguinte faz tudo num script só
        let (ok, out) = powershell(&format!(
            "{RUN_DIR_PS}\nOpen-VantaCancelStream -Path '{p}'\n$a = Test-VantaCancelled\n$w = [IO.File]::Open('{p}', 'Open', 'Write', 'ReadWrite'); $b = [Text.Encoding]::ASCII.GetBytes('cancelar'); $w.Write($b, 0, 8); $w.Dispose()\n'depois=' + (Test-VantaCancelled) + ' antes=' + $a\n",
            p = signal.display()
        ));
        assert!(ok && out.contains("depois=True antes=False"), "{out}");
        // o lado do usuário no Rust escreve exatamente as 8 letras no começo e o tamanho continua 8
        std::fs::write(&signal, [0u8; 8]).unwrap();
        signal_cancel(&signal);
        assert_eq!(std::fs::read(&signal).unwrap(), CANCEL_WORD);
        // só as 8 primeiras letras contam: lixo depois delas não muda a decisão, e 8 letras erradas não cancelam
        std::fs::write(&signal, b"cancelar-e-mais-lixo").unwrap();
        let (_, out) = powershell(&format!(
            "{RUN_DIR_PS}\nOpen-VantaCancelStream -Path '{}'\nTest-VantaCancelled",
            signal.display()
        ));
        assert!(out.contains("True"), "{out}");
        std::fs::write(&signal, b"cancelaX").unwrap();
        let (_, out) = powershell(&format!(
            "{RUN_DIR_PS}\nOpen-VantaCancelStream -Path '{}'\nTest-VantaCancelled",
            signal.display()
        ));
        assert!(out.contains("False"), "{out}");
    }

    #[test]
    fn a_planted_junction_is_refused_before_anything_is_created() {
        let base = tempfile::tempdir().unwrap();
        let elsewhere = tempfile::tempdir().unwrap();
        // \Vanta é uma junção para outra pasta (o ataque: redirecionar o que o lado elevado escreve)
        let link = base.path().join("Vanta");
        let made = Command::new("cmd.exe")
            .args(["/c", "mklink", "/J", &link.to_string_lossy(), &elsewhere.path().to_string_lossy()])
            .output()
            .unwrap();
        assert!(made.status.success(), "{}", String::from_utf8_lossy(&made.stdout));
        let (_, out) = make_run(base.path(), GUID, &format!("'{}'", owner_of(base.path())));
        assert!(out.contains("RECUSADO: ponto de reanálise recusado"), "{out}");
        assert!(!out.contains("FEITO"));
        assert_eq!(
            std::fs::read_dir(elsewhere.path()).unwrap().count(),
            0,
            "nada foi criado atrás da junção"
        );
    }

    #[test]
    fn a_base_that_is_itself_a_junction_is_refused() {
        let real = tempfile::tempdir().unwrap();
        let holder = tempfile::tempdir().unwrap();
        let base = holder.path().join("ProgramData");
        let made = Command::new("cmd.exe")
            .args(["/c", "mklink", "/J", &base.to_string_lossy(), &real.path().to_string_lossy()])
            .output()
            .unwrap();
        assert!(made.status.success());
        let (_, out) = make_run(&base, GUID, &format!("'{}'", owner_of(real.path())));
        assert!(out.contains("RECUSADO: ponto de reanálise recusado"), "{out}");
        assert_eq!(std::fs::read_dir(real.path()).unwrap().count(), 0);
    }

    #[test]
    fn a_junction_at_run_or_at_the_guid_folder_is_refused_too() {
        for deep in ["run", "guid"] {
            let base = tempfile::tempdir().unwrap();
            let elsewhere = tempfile::tempdir().unwrap();
            let owner = owner_of(base.path());
            let writers = format!("'{}'", real_sid());
            let (_, first) = make_run_with(
                base.path(),
                "11111111-1111-1111-1111-111111111111",
                &format!("'{owner}'"),
                &writers,
            );
            assert!(first.contains("FEITO"), "{first}");
            let vanta_run = base.path().join("Vanta").join("run");
            let link = if deep == "run" { vanta_run.clone() } else { vanta_run.join(GUID) };
            if deep == "run" {
                let moved = base.path().join("Vanta").join("run-antigo");
                if std::fs::rename(&vanta_run, &moved).is_err() {
                    continue; // sem direito de renomear (a ACL funcionou): o ataque já não é possível
                }
            }
            let made = Command::new("cmd.exe")
                .args(["/c", "mklink", "/J", &link.to_string_lossy(), &elsewhere.path().to_string_lossy()])
                .output()
                .unwrap();
            if !made.status.success() {
                continue; // a ACL impediu o usuário de plantar: é o que se quer
            }
            let (_, out) = make_run_with(base.path(), GUID, &format!("'{owner}'"), &writers);
            assert!(out.contains("RECUSADO"), "{deep}: {out}");
            assert!(!out.contains("FEITO"), "{deep}: {out}");
            assert_eq!(std::fs::read_dir(elsewhere.path()).unwrap().count(), 0, "{deep}");
        }
    }

    #[test]
    fn a_parent_owned_by_someone_else_is_refused_even_if_it_is_a_plain_folder() {
        let base = tempfile::tempdir().unwrap();
        std::fs::create_dir(base.path().join("Vanta")).unwrap();
        let (_, out) = make_run(base.path(), GUID, "'S-1-5-18'");
        assert!(out.contains("RECUSADO: dono não confiável"), "{out}");
        assert!(!base.path().join("Vanta").join("run").exists());
    }

    #[test]
    fn a_trusted_owner_is_still_refused_when_another_principal_can_write_there() {
        let base = tempfile::tempdir().unwrap();
        std::fs::create_dir(base.path().join("Vanta")).unwrap();
        let (_, out) = make_run(base.path(), GUID, &format!("'{}'", owner_of(&base.path().join("Vanta"))));
        assert!(out.contains("RECUSADO: permissão de escrita para"), "{out}");
        assert!(!base.path().join("Vanta").join("run").exists());
    }

    #[test]
    fn a_fresh_run_dir_is_built_with_the_acl_marker_signal_and_a_protected_chain() {
        let base = tempfile::tempdir().unwrap();
        let owner = owner_of(base.path());
        let writers = format!("'{}'", real_sid());
        let (_, out) = make_run_with(base.path(), GUID, &format!("'{owner}'"), &writers);
        assert!(out.contains("FEITO"), "{out}");
        let dir = run_dir(&base.path().to_string_lossy(), GUID);
        assert_eq!(std::fs::read_to_string(dir.join(RUN_MARKER)).unwrap(), run_marker_text(GUID));
        assert_eq!(std::fs::read(dir.join("cancelar.sinal")).unwrap(), [0u8; 8], "sinal de tamanho fixo");
        let (ok, acl) = powershell(&format!(
            "foreach ($p in '{b}\\Vanta', '{b}\\Vanta\\run', '{d}') {{ $a = [IO.Directory]::GetAccessControl($p); 'PROT=' + $a.AreAccessRulesProtected }}",
            b = base.path().display(),
            d = dir.display()
        ));
        assert!(ok, "{acl}");
        assert_eq!(acl.matches("PROT=True").count(), 3, "{acl}");
        let (_, again) = make_run_with(base.path(), GUID, &format!("'{owner}'"), &writers);
        assert!(again.contains("RECUSADO: a pasta de execução já existe"), "{again}");
        let (_, other) = make_run_with(
            base.path(),
            "22222222-2222-2222-2222-222222222222",
            &format!("'{owner}'"),
            &writers,
        );
        assert!(other.contains("FEITO"), "{other}");
    }

    #[test]
    fn cleanup_removes_only_old_folders_that_are_the_vanta_s_by_name_marker_owner_and_acl() {
        let run = tempfile::tempdir().unwrap();
        let elsewhere = tempfile::tempdir().unwrap();
        std::fs::write(elsewhere.path().join("importante.txt"), "meu").unwrap();
        let old = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"; // do Vanta, antiga, dono e ACL de confiança: sai
        let recent = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
        let no_marker = "cccccccc-cccc-cccc-cccc-cccccccccccc";
        let wrong_marker = "dddddddd-dddd-dddd-dddd-dddddddddddd";
        let junction = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee";
        let not_guid = "minha-pasta";
        for (name, marker, age) in [
            (old, Some(run_marker_text(old)), 3),
            (recent, Some(run_marker_text(recent)), 0),
            (no_marker, None, 3),
            (wrong_marker, Some(run_marker_text(old)), 3),
            (not_guid, Some(run_marker_text(not_guid)), 3),
        ] {
            let dir = run.path().join(name);
            if name == old {
                // a pasta antiga "de verdade": criada com a ACL do Vanta (admin, SYSTEM e o escritor de teste), como o lado
                // elevado a cria; as demais usam a ACL herdada do temporário (outros principais escrevem)
                let (ok, out) = powershell(&format!(
                    "{RUN_DIR_PS}\n$script:VantaTestWriters = @('{w}')\n$null = [IO.Directory]::CreateDirectory('{d}', (New-VantaRunAcl -UserSid '{w}' -Kind Dir))",
                    w = real_sid(),
                    d = dir.display()
                ));
                assert!(ok, "{out}");
            } else {
                std::fs::create_dir(&dir).unwrap();
            }
            std::fs::write(dir.join("dados.txt"), "x").unwrap();
            if let Some(text) = marker {
                std::fs::write(dir.join(RUN_MARKER), text).unwrap();
                let (ok, out) = powershell(&format!(
                    "(Get-Item -LiteralPath '{}' -Force).LastWriteTime = (Get-Date).AddDays(-{age})",
                    dir.join(RUN_MARKER).display()
                ));
                assert!(ok, "{out}");
            }
        }
        let made = Command::new("cmd.exe")
            .args([
                "/c",
                "mklink",
                "/J",
                &run.path().join(junction).to_string_lossy(),
                &elsewhere.path().to_string_lossy(),
            ])
            .output()
            .unwrap();
        assert!(made.status.success());
        // dono confiável e escritor de teste: só a pasta "old" sai; as demais de teste ficam
        let owner = owner_of(run.path());
        let (ok, out) = powershell(&format!(
            "{RUN_DIR_PS}\n$script:VantaTestWriters = @('{w}')\nRemove-VantaStaleRuns -Run '{r}' -TrustedOwners @('{owner}')",
            w = real_sid(),
            r = run.path().display()
        ));
        assert!(ok, "{out}");
        assert!(!run.path().join(old).exists(), "a antiga do Vanta sai");
        for kept in [recent, no_marker, wrong_marker, junction, not_guid] {
            assert!(run.path().join(kept).exists(), "{kept} tem de ficar");
        }
        assert!(elsewhere.path().join("importante.txt").exists(), "o alvo da junção não é tocado");
        // uma pasta antiga, com marca perfeita, mas sem o escritor de teste (a ACL herdada deixa o usuário comum escrever): nada sai
        let forged = "ffffffff-ffff-ffff-ffff-ffffffffffff";
        let forged_dir = run.path().join(forged);
        std::fs::create_dir(&forged_dir).unwrap();
        std::fs::write(forged_dir.join(RUN_MARKER), run_marker_text(forged)).unwrap();
        let (ok, out) = powershell(&format!(
            "(Get-Item -LiteralPath '{}' -Force).LastWriteTime = (Get-Date).AddDays(-3)",
            forged_dir.join(RUN_MARKER).display()
        ));
        assert!(ok, "{out}");
        let (ok, out) =
            powershell(&format!("{RUN_DIR_PS}\nRemove-VantaStaleRuns -Run '{}'", run.path().display()));
        assert!(ok, "{out}");
        assert!(forged_dir.exists(), "marca perfeita não basta: dono e ACL não são do Vanta");
    }

    #[test]
    fn invalid_ids_and_sids_are_refused_by_the_script_itself() {
        let base = tempfile::tempdir().unwrap();
        for (guid, sid) in [("..\\..\\x", USER), (GUID, "S-1-5-18"), (GUID, "S-1-5-21-1;calc")] {
            let script = format!(
                "{RUN_DIR_PS}\ntry {{ New-VantaRunDir -Base '{}' -Guid '{guid}' -UserSid '{sid}'; 'NAO-RECUSOU' }} catch {{ 'RECUSADO' }}",
                base.path().display()
            );
            let (_, out) = powershell(&script);
            assert!(out.contains("RECUSADO") && !out.contains("NAO-RECUSOU"), "{guid} {sid}: {out}");
        }
        assert!(!base.path().join("Vanta").exists());
    }

    #[test]
    fn a_protected_folder_is_created_with_the_acl_or_an_old_loose_one_is_tightened_and_a_foreign_owner_or_junction_is_refused()
     {
        let base = tempfile::tempdir().unwrap();
        let sid = real_sid();
        let owner = owner_of(base.path());
        let run = |path: &Path, trusted: &str| {
            powershell(&format!(
                "{RUN_DIR_PS}\n$script:VantaTestWriters = @('{sid}')\ntry {{ Use-VantaProtectedDir -Path '{}' -UserSid '{sid}' -TrustedOwners @({trusted}); 'FEITO' }} catch {{ 'RECUSADO: ' + $_.Exception.Message }}",
                path.display()
            ))
            .1
        };
        // não existe: criada já com a ACL protegida
        let fresh = base.path().join("Vanta");
        assert!(run(&fresh, &format!("'{owner}'")).contains("FEITO"));
        let (_, prot) = powershell(&format!(
            "[IO.Directory]::GetAccessControl('{}').AreAccessRulesProtected",
            fresh.display()
        ));
        assert!(prot.contains("True"), "{prot}");
        // existe com a ACL frouxa herdada do temporário: o aperto a corrige (era isto que C:\ dava a C:\Vanta)
        let loose = base.path().join("Vanta2");
        fs::create_dir(&loose).unwrap();
        let (_, before) = powershell(&format!(
            "[IO.Directory]::GetAccessControl('{}').AreAccessRulesProtected",
            loose.display()
        ));
        assert!(before.contains("False"), "{before}");
        assert!(run(&loose, &format!("'{owner}'")).contains("FEITO"));
        let (_, after) = powershell(&format!(
            "[IO.Directory]::GetAccessControl('{}').AreAccessRulesProtected",
            loose.display()
        ));
        assert!(after.contains("True"), "{after}");
        // dono que não é de confiança: recusada e a ACL não é mexida
        let foreign = base.path().join("Vanta3");
        fs::create_dir(&foreign).unwrap();
        assert!(run(&foreign, "'S-1-5-18'").contains("RECUSADO: dono não confiável"));
        let (_, still) = powershell(&format!(
            "[IO.Directory]::GetAccessControl('{}').AreAccessRulesProtected",
            foreign.display()
        ));
        assert!(still.contains("False"), "{still}");
        // junção: recusada
        let elsewhere = tempfile::tempdir().unwrap();
        let link = base.path().join("Vanta4");
        let made = Command::new("cmd.exe")
            .args(["/c", "mklink", "/J", &link.to_string_lossy(), &elsewhere.path().to_string_lossy()])
            .output()
            .unwrap();
        assert!(made.status.success());
        assert!(run(&link, &format!("'{owner}'")).contains("RECUSADO: ponto de reanálise"));
    }
}
