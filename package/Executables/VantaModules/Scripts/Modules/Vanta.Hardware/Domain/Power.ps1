# Vanta.Hardware domain: the Vanta power scheme.
#
# 'Vanta' duplicates the scheme the user has active (so screen and sleep timeouts and every DC value are kept), applies
# three AC settings and activates the copy. The copy gets a GUID chosen by Windows (/duplicatescheme without a target),
# recorded in the Vanta services state key together with the previously active scheme; no fixed GUID is ever used, so a
# plan of another program (for example the Atlas Power Scheme) can never be taken for ours. 'Default' reactivates the
# remembered scheme (or Balanced when it is gone) and deletes the Vanta scheme, but ONLY when the recorded GUID still has
# the Vanta plan name. Every powercfg call is exit-code checked and the final active scheme is verified.

# 381b4222-f694-41f0-9685-ff5bb260df2e is the Windows Balanced scheme (SCHEME_BALANCED).
$script:BalancedPowerScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PowerStateSubKey = 'SOFTWARE\Vanta\Services\PowerSaving'
$script:PowerStateValue = 'PreviousPowerSchemeGuid'
$script:OwnPowerStateValue = 'VantaPowerSchemeGuid'
$script:VantaPowerSchemeName = 'Vanta Power Scheme'
$script:PowerTransactionMutexName = 'Global\Vanta.PowerSaving.Transaction.v1'

function ConvertTo-VantaPowerSchemeGuid {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value
    )

    $guid = [guid]::Empty
    if (-not [guid]::TryParse($Value, [ref]$guid) -or $guid -eq [guid]::Empty) {
        throw "Invalid power-scheme GUID '$Value'."
    }
    return $guid.ToString('D').ToLowerInvariant()
}

function Invoke-VantaPowerCfg {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    # Redirected stderr becomes an error record, which Stop would throw before the
    # exit code is read; keep it as output so the exit code decides.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($null -eq $exitCode -or [int]$exitCode -ne 0) {
        $detail = (@($output | ForEach-Object { [string]$_ }) -join ' ').Trim()
        throw "powercfg.exe $($ArgumentList -join ' ') failed with exit code '$exitCode'. $detail"
    }
    return [string[]]@($output | ForEach-Object { [string]$_ })
}

function Get-VantaPowerSchemeGuidFromOutput {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Output,

        [switch]$RequireSingle
    )

    $text = $Output -join "`n"
    $guids = @([regex]::Matches(
            $text,
            '(?i)(?<![0-9a-f])[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}(?![0-9a-f])'
        ) | ForEach-Object {
            ConvertTo-VantaPowerSchemeGuid -Value $_.Value
        } | Sort-Object -Unique)
    if ($RequireSingle -and $guids.Count -ne 1) {
        throw "Expected one power-scheme GUID, found $($guids.Count)."
    }
    return [string[]]$guids
}

function Get-VantaActivePowerScheme {
    param([Parameter(Mandatory = $true)][string]$PowerCfgPath)

    return @(Get-VantaPowerSchemeGuidFromOutput `
            -Output (Invoke-VantaPowerCfg -FilePath $PowerCfgPath `
                -ArgumentList @('/getactivescheme')) `
            -RequireSingle)[0]
}

function Get-VantaPowerSchemeInventory {
    param([Parameter(Mandatory = $true)][string]$PowerCfgPath)

    return @(Get-VantaPowerSchemeGuidFromOutput `
            -Output (Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/l')))
}

function Test-VantaPowerSchemeStored {
    <#
    .SYNOPSIS
        Returns whether Windows stores a power plan with the given GUID, listed or not.
    .DESCRIPTION
        Modern Standby PCs list only Balanced and plans copied from it, but an unlisted
        plan, such as the Ultimate Performance copy older Vanta versions made, still
        holds its GUID: /duplicatescheme then refuses it. Windows keeps each plan as a
        key under User\PowerSchemes.
    #>
    param([Parameter(Mandatory = $true)][string]$SchemeGuid)

    $scheme = ConvertTo-VantaPowerSchemeGuid -Value $SchemeGuid
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.OpenSubKey("SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$scheme", $false)
        return $null -ne $key
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Get-VantaPreviousPowerScheme {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.OpenSubKey($script:PowerStateSubKey, $false)
        if ($null -eq $key -or
            -not @($key.GetValueNames()).Contains($script:PowerStateValue)) {
            return $null
        }
        if ($key.GetValueKind($script:PowerStateValue) -ne
            [Microsoft.Win32.RegistryValueKind]::String) {
            throw 'The saved Vanta power scheme has an unexpected registry type.'
        }
        return ConvertTo-VantaPowerSchemeGuid -Value ([string]$key.GetValue(
                $script:PowerStateValue,
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            ))
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Save-VantaPreviousPowerScheme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SchemeGuid
    )

    $existing = Get-VantaPreviousPowerScheme
    if ($null -ne $existing) {
        return $existing
    }

    $scheme = ConvertTo-VantaPowerSchemeGuid -Value $SchemeGuid
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.CreateSubKey($script:PowerStateSubKey)
        $key.SetValue(
            $script:PowerStateValue,
            $scheme,
            [Microsoft.Win32.RegistryValueKind]::String
        )
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }

    $saved = Get-VantaPreviousPowerScheme
    if ($saved -cne $scheme) {
        throw 'The previous power-scheme state was not saved.'
    }
    return $saved
}

function Clear-VantaPreviousPowerScheme {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedSchemeGuid
    )

    $expected = ConvertTo-VantaPowerSchemeGuid -Value $ExpectedSchemeGuid
    $current = Get-VantaPreviousPowerScheme
    if ($null -eq $current) {
        return
    }
    if ($current -cne $expected) {
        throw 'The saved power scheme changed before it could be cleared.'
    }

    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.OpenSubKey($script:PowerStateSubKey, $true)
        if ($null -ne $key) {
            $key.DeleteValue($script:PowerStateValue, $false)
        }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Get-VantaOwnPowerScheme {
    <# O GUID do plano que ESTE Vanta criou (guardado na chave de estado), ou $null. Nunca um GUID fixo: o Windows escolhe
       o GUID no /duplicatescheme, então não colide com planos de terceiros (por exemplo o Atlas). #>
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.OpenSubKey($script:PowerStateSubKey, $false)
        if ($null -eq $key -or -not @($key.GetValueNames()).Contains($script:OwnPowerStateValue)) { return $null }
        $text = [string]$key.GetValue($script:OwnPowerStateValue, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $guid = [guid]::Empty
        if (-not [guid]::TryParse($text, [ref]$guid) -or $guid -eq [guid]::Empty) { return $null }
        return $guid.ToString('D').ToLowerInvariant()
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Save-VantaOwnPowerScheme {
    param([Parameter(Mandatory = $true)][string]$SchemeGuid)
    $scheme = ConvertTo-VantaPowerSchemeGuid -Value $SchemeGuid
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.CreateSubKey($script:PowerStateSubKey)
        $key.SetValue($script:OwnPowerStateValue, $scheme, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Clear-VantaOwnPowerScheme {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $null
    try {
        $key = $baseKey.OpenSubKey($script:PowerStateSubKey, $true)
        if ($null -ne $key) { $key.DeleteValue($script:OwnPowerStateValue, $false) }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        $baseKey.Dispose()
    }
}

function Test-VantaOwnPowerScheme {
    <# Prova de autoria: o GUID está registrado como nosso E o plano ainda tem o nome do Vanta (na lista do powercfg ou, se o
       Modern Standby deixou o plano fora da lista, no FriendlyName guardado no registro). Um plano de outro programa ou do
       usuário nunca passa, mesmo que tenha o mesmo GUID. #>
    param(
        [Parameter(Mandatory = $true)][string]$PowerCfgPath,
        [Parameter(Mandatory = $true)][string]$SchemeGuid
    )
    $scheme = ConvertTo-VantaPowerSchemeGuid -Value $SchemeGuid
    $own = Get-VantaOwnPowerScheme
    if ($null -eq $own -or $own -cne $scheme) { return $false }
    $name = [regex]::Escape($script:VantaPowerSchemeName)
    foreach ($line in @(Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/l'))) {
        if ($line -match [regex]::Escape($scheme) -and $line -match "\($name\)") { return $true }
    }
    try {
        $friendly = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$scheme" -Name FriendlyName -ErrorAction Stop).FriendlyName
        return [string]$friendly -ceq $script:VantaPowerSchemeName
    }
    catch { return $false }
}

function Get-VantaPowerPlanTimeout {
    <# Tempo (segundos) de AC e de bateria de um ajuste de um plano, lido de `powercfg /query`: as duas últimas linhas 0x........
       são o valor atual em AC e em DC, em qualquer idioma. Lança erro se a leitura falhar. #>
    param(
        [Parameter(Mandatory = $true)][string]$PowerCfgPath,
        [Parameter(Mandatory = $true)][string]$SchemeGuid,
        [Parameter(Mandatory = $true)][string]$SubGroup,
        [Parameter(Mandatory = $true)][string]$Setting
    )
    $output = @(Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/query', $SchemeGuid, $SubGroup, $Setting))
    $hex = @([regex]::Matches(($output -join "`n"), '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -lt 2) { throw "Could not read $Setting of power scheme $SchemeGuid." }
    return [pscustomobject]@{ Ac = [Convert]::ToInt64($hex[$hex.Count - 2], 16); Dc = [Convert]::ToInt64($hex[$hex.Count - 1], 16) }
}

function Assert-VantaPowerTimeoutsPreserved {
    <# Confere que a cópia tem os 4 tempos do plano de origem (tela e suspensão, AC e bateria). Lança erro se algum divergir:
       quem chama descarta a cópia e mantém o plano atual ativo. #>
    param(
        [Parameter(Mandatory = $true)][string]$PowerCfgPath,
        [Parameter(Mandatory = $true)][string]$From,
        [Parameter(Mandatory = $true)][string]$To
    )
    foreach ($setting in @(@('SUB_VIDEO', 'VIDEOIDLE'), @('SUB_SLEEP', 'STANDBYIDLE'))) {
        $original = Get-VantaPowerPlanTimeout -PowerCfgPath $PowerCfgPath -SchemeGuid $From -SubGroup $setting[0] -Setting $setting[1]
        $copy = Get-VantaPowerPlanTimeout -PowerCfgPath $PowerCfgPath -SchemeGuid $To -SubGroup $setting[0] -Setting $setting[1]
        if ($original.Ac -ne $copy.Ac -or $original.Dc -ne $copy.Dc) {
            throw "$($setting[1]) of the copied power scheme (AC $($copy.Ac), DC $($copy.Dc)) differs from the active one (AC $($original.Ac), DC $($original.Dc))."
        }
    }
}

function Invoke-VantaPowerSavingState {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Vanta', 'Default')]
        [string]$RequestedMode,

        [Parameter(Mandatory = $true)]
        [string]$PowerCfgPath
    )

    $installed = @(Get-VantaPowerSchemeInventory -PowerCfgPath $PowerCfgPath)
    if ($installed -cnotcontains $script:BalancedPowerScheme) {
        throw 'The Windows Balanced power scheme is not installed.'
    }
    # só é "nosso" o plano que o diário/estado registrou E que ainda tem o nome do Vanta; nada mais é apagado
    $own = Get-VantaOwnPowerScheme
    $ownProven = $false
    if ($null -ne $own) {
        $ownProven = [bool](Test-VantaOwnPowerScheme -PowerCfgPath $PowerCfgPath -SchemeGuid $own)
    }

    $savedToClear = $null
    if ($RequestedMode -ceq 'Vanta') {
        $active = Get-VantaActivePowerScheme -PowerCfgPath $PowerCfgPath
        if ($installed -cnotcontains $active) {
            throw "The active power scheme '$active' is not installed."
        }
        # a base é SEMPRE o plano ativo: se for o próprio plano do Vanta, é nele que estão os tempos que o usuário
        # personalizou depois; o plano antigo só sai depois de o substituto estar pronto, conferido e ativo
        $replacing = $ownProven -and $active -ceq $own
        if (-not $replacing) {
            [void](Save-VantaPreviousPowerScheme -SchemeGuid $active)
        }
        $oldOwn = if ($ownProven) { $own } else { $null }

        # sem GUID de destino: o Windows escolhe um GUID novo e o imprime
        $created = @(Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/duplicatescheme', $active))
        $new = @(Get-VantaPowerSchemeGuidFromOutput -Output $created -RequireSingle)[0]
        if ($null -eq $oldOwn) {
            Save-VantaOwnPowerScheme -SchemeGuid $new
        }
        try {
            [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath `
                    -ArgumentList @(
                        '/changename',
                        $new,
                        $script:VantaPowerSchemeName,
                        'Vanta AC power policy with documented Windows settings.'
                    ))
            # os 4 tempos (tela e suspensão, AC e bateria) do plano ativo têm de estar na cópia antes de qualquer troca
            Assert-VantaPowerTimeoutsPreserved -PowerCfgPath $PowerCfgPath -From $active -To $new

            # Subgroup GUID, setting GUID, AC value; docs/power-saving-policy.md lists each one:
            # Hard disk > NVMe NOPPME off; Processor power management > Allow Throttle States
            # off; Processor power management > Processor performance time check interval 200 ms.
            # The display and sleep timeouts are NOT touched: the plan is a copy of the user's own.
            foreach ($setting in @(
                    @('0012ee47-9041-4b5d-9b77-535fba8b1442', 'fc7372b6-ab2d-43ee-8797-15e9841f2cca', '0'),
                    @('54533251-82be-4824-96c1-47b60b740d00', '3b04d4fd-1cc7-4f23-ab1c-d1337819c4bb', '0'),
                    @('54533251-82be-4824-96c1-47b60b740d00', '4d2b0152-7d5c-498b-88e2-34345392a2c5', '200')
                )) {
                [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath `
                        -ArgumentList @('/setacvalueindex', $new, $setting[0], $setting[1], $setting[2]))
            }
            [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/setactive', $new))
        }
        catch {
            # só o plano que acabamos de criar (autoria conhecida) é descartado; o plano ativo e o antigo do Vanta ficam
            $failure = $_
            try { [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/delete', $new)) } catch { Write-Verbose "delete new failed: $($_.Exception.Message)" }
            if ($null -eq $oldOwn) { Clear-VantaOwnPowerScheme }
            throw $failure
        }
        # o substituto está ativo: agora o registro aponta para ele e só então o plano antigo do Vanta sai
        if ($null -ne $oldOwn) {
            Save-VantaOwnPowerScheme -SchemeGuid $new
            try { [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/delete', $oldOwn)) } catch { Write-Warning "The previous Vanta power scheme could not be deleted: $($_.Exception.Message)" }
        }
        $expectedActive = $new
    }
    else {
        $saved = Get-VantaPreviousPowerScheme
        $target = if ($null -ne $saved -and
            $saved -cne $own -and
            $installed -ccontains $saved) {
            $saved
        }
        else {
            $script:BalancedPowerScheme
        }

        [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/setactive', $target))
        if ($ownProven) {
            [void](Invoke-VantaPowerCfg -FilePath $PowerCfgPath -ArgumentList @('/delete', $own))
        }
        if ($null -ne $own) {
            Clear-VantaOwnPowerScheme
        }
        if ($null -ne $saved) {
            $savedToClear = $saved
        }
        $expectedActive = $target
    }

    $activeAfter = Get-VantaActivePowerScheme -PowerCfgPath $PowerCfgPath
    if ($activeAfter -cne $expectedActive) {
        throw "The active power scheme is '$activeAfter'; expected '$expectedActive'."
    }
    if ($null -ne $savedToClear) {
        Clear-VantaPreviousPowerScheme -ExpectedSchemeGuid $savedToClear
    }
}

function Set-VantaPowerSavingState {
    <#
    .SYNOPSIS
        Applies the Vanta AC power policy (Mode Vanta) or restores the previously
        active power plan and removes the Vanta plan (Mode Default). Requires
        Administrator rights; concurrent Vanta power operations are serialised.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Vanta', 'Default')]
        [string]$Mode,

        [switch]$Silent
    )

    Assert-VantaPrivilege -Administrator

    $powerCfgPath = [IO.Path]::Combine([Environment]::SystemDirectory, 'powercfg.exe')
    if (-not [IO.File]::Exists($powerCfgPath)) {
        throw "Windows powercfg.exe was not found at '$powerCfgPath'."
    }

    $mutex = New-Object Threading.Mutex($false, $script:PowerTransactionMutexName)
    $ownsMutex = $false
    try {
        try {
            $ownsMutex = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
        }
        catch [Threading.AbandonedMutexException] {
            $ownsMutex = $true
        }
        if (-not $ownsMutex) {
            throw 'Timed out waiting for another Vanta power operation to finish.'
        }

        if (-not $Silent) {
            Write-VantaStep -Text $(if ($Mode -ceq 'Vanta') {
                    'Applying the Vanta AC power policy...'
                }
                else {
                    'Restoring the previous power plan...'
                })
        }
        Invoke-VantaPowerSavingState -RequestedMode $Mode -PowerCfgPath $powerCfgPath
    }
    finally {
        if ($ownsMutex) {
            [void]$mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }

    Write-VantaLog -Message "Power-saving mode '$Mode' applied."
}
