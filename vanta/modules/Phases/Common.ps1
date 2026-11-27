# Funções comuns das fases Vanta. Compatível com Windows PowerShell 5.1 (roda dentro do orquestrador do Vanta).
# Cada fase recebe o contexto do Vanta (Get-VantaContext): Mode (Fresh/Upgrade/Reapply/Rebase), Options,
# InteractiveUserSid, WinDir. Os testes passam um contexto falso e fazem mock destas funções.

function Write-VantaPhaseLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('Info', 'Warning')][string]$Level = 'Info'
    )
    # Mesmo log do Vanta: o Manager mostra e o diagnóstico coleta.
    if (Get-Command -Name Write-VantaLog -ErrorAction SilentlyContinue) {
        if ($Level -eq 'Warning') { Write-VantaLog -Level Warning -Message "Vanta: $Message" }
        else { Write-VantaLog -Message "Vanta: $Message" }
    }
    else {
        Write-Host "[Vanta] $Level $Message"
    }
}

function Test-VantaPhaseOption {
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][string]$Id)
    return (@($Context.Options) -ccontains $Id)
}

function Get-VantaModulesRoot {
    # ...\VantaModules\Vanta (esta pasta é Phases\)
    return (Split-Path -Path $PSScriptRoot -Parent)
}

function Get-VantaEdition {
    <# 'pessoal' ou 'publico', gravado pelo build em Vanta\edition.txt. Pacote sem o arquivo (o de antes das edições) = 'pessoal'. #>
    param([string]$ModulesRoot = (Get-VantaModulesRoot))
    $file = Join-Path -Path $ModulesRoot -ChildPath 'edition.txt'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return 'pessoal' }
    $text = ([IO.File]::ReadAllText($file)).Trim()
    if ($text -cnotin 'pessoal', 'publico') { throw "edition.txt tem '$text'; esperado 'pessoal' ou 'publico'." }
    return $text
}

function Get-VantaToolsRoot {
    param([string]$SystemDrive = $env:SystemDrive)
    if ([string]::IsNullOrWhiteSpace($SystemDrive)) { $SystemDrive = 'C:' }
    return (Join-Path -Path $SystemDrive -ChildPath 'Vanta\Tools')
}

function Get-VantaUserProfile {
    <# Perfil do usuário que instalou (o certo, não SYSTEM nem TrustedInstaller). $null se não achar. #>
    param([Parameter(Mandatory = $true)][string]$Sid)
    if ($Sid -notmatch '^S-1-5-21-[\d-]+$') { return $null }
    $key = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$Sid"
    $item = Get-ItemProperty -LiteralPath $key -Name ProfileImagePath -ErrorAction SilentlyContinue
    if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item.ProfileImagePath)) { return $null }
    return [Environment]::ExpandEnvironmentVariables([string]$item.ProfileImagePath)
}

function Get-VantaUserRunOnceKey {
    param([Parameter(Mandatory = $true)][string]$Sid)
    return "Registry::HKEY_USERS\$Sid\Software\Microsoft\Windows\CurrentVersion\RunOnce"
}

function Set-VantaUserRunOnce {
    <# RunOnce no hive do usuário certo (HKU\<sid>). Confere que o hive está carregado; cria a subchave RunOnce se faltar. #>
    param(
        [Parameter(Mandatory = $true)][string]$Sid,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Command
    )
    $hive = "Registry::HKEY_USERS\$Sid"
    if (-not (Test-Path -LiteralPath $hive)) {
        Write-VantaPhaseLog -Level Warning -Message "O hive do usuário $Sid não está carregado; RunOnce '$Name' não gravado."
        return $false
    }
    $key = Get-VantaUserRunOnceKey -Sid $Sid
    if (-not (Test-Path -LiteralPath $key)) {
        # só a subchave que falta, nível por nível (o hive existe; nada é recriado por cima)
        $current = $hive
        foreach ($part in 'Software', 'Microsoft', 'Windows', 'CurrentVersion', 'RunOnce') {
            $current = "$current\$part"
            if (-not (Test-Path -LiteralPath $current)) { $null = New-Item -Path $current }
        }
    }
    New-ItemProperty -LiteralPath $key -Name $Name -Value $Command -PropertyType String -Force | Out-Null
    return $true
}

function Get-VantaRawRegValue {
    <# Valor de HKU\<sid>\<subchave> SEM expandir %VAR% (Get-ItemProperty expandiria com o ambiente de quem roda a fase).
       Devolve @{ Status = 'Found'|'Missing'|'Error'; Value }: falha de leitura não se confunde com valor ausente. #>
    param(
        [Parameter(Mandatory = $true)][string]$Sid,
        [Parameter(Mandatory = $true)][string]$SubKey,
        [Parameter(Mandatory = $true)][string]$Name
    )
    try {
        $key = [Microsoft.Win32.Registry]::Users.OpenSubKey("$Sid\$SubKey", $false)
        if ($null -eq $key) { return @{ Status = 'Missing'; Value = $null } }
        try {
            $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        finally { $key.Close() }
        if ($null -eq $value) { return @{ Status = 'Missing'; Value = $null } }
        return @{ Status = 'Found'; Value = [string]$value }
    }
    catch { return @{ Status = 'Error'; Value = $null } }
}

function Expand-VantaUserPath {
    <# Expande %VAR% com o ambiente do USUÁRIO efetivo (%USERPROFILE% = o perfil dele; o resto, de HKU\<sid>\Environment,
       onde o OneDrive grava %OneDrive%). Nunca com o ambiente de quem roda a fase. $null se sobrar variável sem valor. #>
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Sid,
        [Parameter(Mandatory = $true)][string]$ProfilePath
    )
    $resolved = [regex]::Replace($Value, '%([^%\r\n]+)%', [Text.RegularExpressions.MatchEvaluator]{
            param($m)
            $name = $m.Groups[1].Value
            if ($name -ieq 'USERPROFILE') { return $ProfilePath }
            $raw = Get-VantaRawRegValue -Sid $Sid -SubKey 'Environment' -Name $name
            $text = if ($raw.Status -eq 'Found') { $raw.Value } else { '' }
            if ([string]::IsNullOrWhiteSpace($text)) { return $m.Value }
            return $text
        })
    if ($resolved -match '%[^%\r\n]+%') { return $null }
    return $resolved
}

function Get-VantaUserShellFolder {
    <# Pasta conhecida do usuário (Desktop, Programs) lida de HKU\<sid>\...\User Shell Folders: acompanha o OneDrive e
       qualquer redirecionamento, expandido com o ambiente DO USUÁRIO. Devolve $null (e o chamador omite o atalho com
       aviso) se o hive não está carregado ou se sobra uma variável sem valor: nunca presume <perfil>\Desktop quando
       não pode ler a pasta de verdade. Hive carregado e sem entrada: a pasta padrão do perfil. #>
    param(
        [Parameter(Mandatory = $true)][string]$Sid,
        [Parameter(Mandatory = $true)][ValidateSet('Desktop', 'Programs')][string]$Name,
        [Parameter(Mandatory = $true)][string]$ProfilePath
    )
    if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$Sid")) { return $null }
    $default = @{ Desktop = 'Desktop'; Programs = 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs' }[$Name]
    $raw = Get-VantaRawRegValue -Sid $Sid -Name $Name -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    if ($raw.Status -eq 'Error') { return $null }   # não leu: não presume a pasta padrão
    $value = if ($raw.Status -eq 'Found') { $raw.Value } else { '' }
    if ([string]::IsNullOrWhiteSpace($value)) { return (Join-Path $ProfilePath $default) }
    return (Expand-VantaUserPath -Value $value -Sid $Sid -ProfilePath $ProfilePath)
}

$script:VantaTrustedOwnerSids = @(
    'S-1-5-18',                                                           # SYSTEM
    'S-1-5-32-544',                                                       # Administradores
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'      # TrustedInstaller
)

function Get-VantaOwnerSid {
    param([Parameter(Mandatory = $true)][string]$Path)
    try { return [string](Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value }
    catch { return $null }
}

function Test-VantaReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Assert-VantaTrustedFolder {
    <# Uma pasta que já existe só serve se não é junção/link e pertence ao sistema, ao TrustedInstaller ou aos
       administradores. Um usuário comum pode criar C:\Vanta: a pasta dele não é de confiança. #>
    param([Parameter(Mandatory = $true)][string]$Path, [string]$What = 'Pasta')
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (Test-VantaReparsePoint -Path $Path) { throw "$What '$Path' é uma junção ou link; recusado." }
    $owner = Get-VantaOwnerSid -Path $Path
    if (-not $owner -or $owner -cnotin $script:VantaTrustedOwnerSids) {
        throw "$What '$Path' pertence a '$owner', que não é o sistema nem um administrador; recusado."
    }
}

function Protect-VantaFolder {
    <# Só administradores e o sistema escrevem; os usuários leem e executam. Sem herança do pai. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [Security.AccessControl.PropagationFlags]::None
    foreach ($row in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $sid = New-Object Security.Principal.SecurityIdentifier($row[0])
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid, $row[1], $inherit, $none, 'Allow')))
    }
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Get-VantaPhaseSkipReason {
    <# Uma fase que depende de outra não roda se a outra falhou. $null = pode rodar. #>
    param([Parameter(Mandatory = $true)][string]$Name, [string[]]$Failed = @())
    $needs = @{ Shortcuts = 'Tools' }
    if ($needs.ContainsKey($Name) -and $Failed -ccontains $needs[$Name]) {
        return "a fase '$($needs[$Name])' falhou; '$Name' não roda com um Tools que não foi copiado e conferido."
    }
    return $null
}
function New-VantaPhaseShortcut {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Arguments = '',
        [string]$WorkingDirectory = '',
        [string]$IconLocation = '',
        [int]$WindowStyle = 1
    )
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Path $Path -Parent)
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($Path)
    $link.TargetPath = $Target
    $link.Arguments = $Arguments   # sempre: um atalho antigo (edição pessoal) não pode manter argumentos de antes
    if ($WorkingDirectory) { $link.WorkingDirectory = $WorkingDirectory }
    $link.IconLocation = $(if ($IconLocation) { $IconLocation } else { $Target })
    $link.WindowStyle = $WindowStyle
    $link.Save()
}

function Register-VantaToolsTask {
    <# Tarefa agendada \Vanta\VantaTools: só vanta-tools.exe, sem argumentos, com os maiores privilégios do usuário que
       instalou (RunLevel Highest, token interativo: o "Elevated Task Model" da Microsoft). A tarefa só deixa SYSTEM e
       Administrators editarem; o usuário instalador pode ler e executar (sddl). Exige processo elevado/SYSTEM. #>
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string]$Sid,
        [string]$TaskPath = '\Vanta',
        [string]$TaskName = 'VantaTools'
    )
    if ($Sid -notmatch '^S-1-5-21-[\d-]+$') { throw "Tarefa: SID inválido '$Sid'." }
    $user = (New-Object Security.Principal.SecurityIdentifier($Sid)).Translate([Security.Principal.NTAccount]).Value
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $root = $service.GetFolder('\')
    try { $folder = $root.GetFolder($TaskPath) } catch { $folder = $root.CreateFolder($TaskPath) }
    $definition = $service.NewTask(0)
    $definition.RegistrationInfo.Description = 'Abre o Vanta Tools já elevado. Só executa vanta-tools.exe, sem argumentos.'
    $definition.Principal.UserId = $user
    $definition.Principal.LogonType = 3   # TASK_LOGON_INTERACTIVE_TOKEN
    $definition.Principal.RunLevel = 1    # TASK_RUNLEVEL_HIGHEST
    $definition.Settings.Enabled = $true
    $definition.Settings.AllowDemandStart = $true
    $definition.Settings.DisallowStartIfOnBatteries = $false
    $definition.Settings.StopIfGoingOnBatteries = $false
    $definition.Settings.MultipleInstances = 2   # IgnoreNew
    $definition.Settings.ExecutionTimeLimit = 'PT0S'
    $action = $definition.Actions.Create(0)
    $action.Path = $Exe
    $action.WorkingDirectory = Split-Path -Path $Exe -Parent
    $sddl = "D:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;GRGX;;;$Sid)"
    $null = $folder.RegisterTaskDefinition($TaskName, $definition, 6, $null, $null, 3, $sddl)
}

function Assert-VantaToolsFileHardened {
    <# Um arquivo ou pasta da cadeia da tarefa 2B (ela roda este exe elevada): só SYSTEM e Administrators escrevem, criam,
       apagam ou trocam permissões. Em pasta isto vale também para apagar/substituir o que está dentro dela. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $trusted = 'S-1-5-18', 'S-1-5-32-544'
    $writes = [Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteAttributes, WriteExtendedAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
    $acl = Get-Acl -LiteralPath $Path
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne 'Allow' -or -not ($rule.FileSystemRights -band $writes)) { continue }
        # Uma regra só para os filhos não vale para este item.
        if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        $who = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($who -notin $trusted) { throw "Tools: '$Path' deixa '$($rule.IdentityReference)' escrever, apagar ou substituir; só SYSTEM e Administrators podem." }
    }
}

function Test-VantaNotFoundError {
    <# Só "arquivo/caminho não encontrado" (0x80070002/0x80070003) é ausência; qualquer outra falha do agendador é erro. #>
    param([Parameter(Mandatory = $true)]$ErrorRecord)
    for ($e = $ErrorRecord.Exception; $null -ne $e; $e = $e.InnerException) {
        if ($e.HResult -in -2147024894, -2147024893) { return $true }
    }
    return $false
}

function Get-VantaTaskInfo {
    <# A definição inteira da tarefa (ações com argumentos e pasta, principal e nível), para comparar com a que o Vanta
       registra. Ausente ({Present=$false}) só quando o agendador diz "não encontrado"; outro erro sobe. Os testes fazem mock aqui. #>
    param([string]$TaskPath = '\Vanta', [string]$TaskName = 'VantaTools')
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    try {
        $task = $service.GetFolder($TaskPath).GetTask($TaskName)
    }
    catch {
        if (Test-VantaNotFoundError -ErrorRecord $_) { return [pscustomobject]@{ Present = $false; Actions = @() } }
        throw
    }
    $definition = $task.Definition
    return [pscustomobject]@{
        Present   = $true
        Actions   = @(@($definition.Actions) | ForEach-Object { [pscustomobject]@{ Type = [int]$_.Type; Path = [string]$_.Path; Arguments = [string]$_.Arguments; WorkingDirectory = [string]$_.WorkingDirectory } })
        UserId    = [string]$definition.Principal.UserId
        LogonType = [int]$definition.Principal.LogonType
        RunLevel  = [int]$definition.Principal.RunLevel
    }
}

function Resolve-VantaAccountSid {
    <# O SID de uma conta ("DOMINIO\usuario" ou já um SID). Os testes fazem mock aqui. #>
    param([Parameter(Mandatory = $true)][string]$Account)
    if ($Account -match '^S-1-') { return $Account }
    return (New-Object Security.Principal.NTAccount($Account)).Translate([Security.Principal.SecurityIdentifier]).Value
}

function Get-VantaTaskMismatch {
    <# O que difere entre a tarefa encontrada e a que Register-VantaToolsTask grava (uma ação Execute: o exe, sem
       argumentos, na pasta dele; principal do usuário instalador, token interativo, privilégios máximos). Vazio = é a do Vanta. #>
    param([Parameter(Mandatory = $true)]$Info, [Parameter(Mandatory = $true)][string]$Exe, [Parameter(Mandatory = $true)][string]$Sid)
    $problems = [Collections.Generic.List[string]]::new()
    $actions = @($Info.Actions)
    if ($actions.Count -ne 1) { $problems.Add("$($actions.Count) ação(ões)") }
    else {
        $action = $actions[0]
        if ($action.Type -ne 0) { $problems.Add('ação que não é executar programa') }
        if ($action.Path -ine $Exe) { $problems.Add("executável '$($action.Path)'") }
        if (-not [string]::IsNullOrEmpty($action.Arguments)) { $problems.Add("argumentos '$($action.Arguments)'") }
        if (([string]$action.WorkingDirectory).TrimEnd([char]92) -ine (Split-Path -Path $Exe -Parent)) { $problems.Add("pasta de trabalho '$($action.WorkingDirectory)'") }
    }
    if ($Info.LogonType -ne 3) { $problems.Add("tipo de logon $($Info.LogonType)") }
    if ($Info.RunLevel -ne 1) { $problems.Add("nível de execução $($Info.RunLevel)") }
    $owner = $null
    try { $owner = Resolve-VantaAccountSid -Account ([string]$Info.UserId) } catch { $owner = $null }
    if ($owner -cne $Sid) { $problems.Add("conta '$($Info.UserId)'") }
    return @($problems)
}

function Invoke-VantaTaskDelete {
    param([string]$TaskPath = '\Vanta', [string]$TaskName = 'VantaTools')
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $service.GetFolder($TaskPath).DeleteTask($TaskName, 0)
}

function Remove-VantaToolsTask {
    <# Remove a tarefa elevada \Vanta\VantaTools (a edição pública nunca deixa nada rodando sem UAC). Só apaga uma tarefa
       cuja definição COMPLETA é a que o Vanta registra (executável, argumentos, pasta, principal, nível); qualquer
       divergência é colisão: a tarefa fica e a fase para. Depois de apagar, confirma que sumiu.
       Devolve $true se removeu, $false se não havia. #>
    param([Parameter(Mandatory = $true)][string]$Exe, [Parameter(Mandatory = $true)][string]$Sid, [string]$TaskPath = '\Vanta', [string]$TaskName = 'VantaTools')
    $info = Get-VantaTaskInfo -TaskPath $TaskPath -TaskName $TaskName
    if (-not $info.Present) { return $false }
    $mismatch = @(Get-VantaTaskMismatch -Info $info -Exe $Exe -Sid $Sid)
    if ($mismatch.Count -gt 0) {
        throw "Tarefa: '$TaskPath\$TaskName' existe mas não é a que o Vanta registra (colisão: $($mismatch -join '; ')); foi preservada."
    }
    Invoke-VantaTaskDelete -TaskPath $TaskPath -TaskName $TaskName
    if ((Get-VantaTaskInfo -TaskPath $TaskPath -TaskName $TaskName).Present) {
        throw "Tarefa: '$TaskPath\$TaskName' continua registrada depois de apagada."
    }
    return $true
}

function Test-VantaToolsTask {
    <# $true só se a tarefa existe e faz exatamente isto: um único comando, vanta-tools.exe, sem argumentos, RunLevel Highest. #>
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [string]$TaskPath = '\Vanta',
        [string]$TaskName = 'VantaTools'
    )
    try {
        $service = New-Object -ComObject Schedule.Service
        $service.Connect()
        $task = $service.GetFolder($TaskPath).GetTask($TaskName)
        $actions = @($task.Definition.Actions)
        return ($task.Enabled -and $actions.Count -eq 1 -and $actions[0].Path -ieq $Exe -and
            [string]::IsNullOrEmpty($actions[0].Arguments) -and $task.Definition.Principal.RunLevel -eq 1)
    }
    catch { return $false }
}

function Invoke-VantaPhasePowerCfg {
    # Ponto único de chamada do powercfg (os testes fazem mock aqui).
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & "$env:SystemRoot\System32\powercfg.exe" @Arguments 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Test-VantaBattery {
    return ($null -ne (Get-CimInstance -ClassName Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Get-VantaLogicalProcessorCount {
    return [Environment]::ProcessorCount
}
