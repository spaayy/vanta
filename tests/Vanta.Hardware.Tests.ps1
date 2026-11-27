BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Core\Vanta.Core.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Hardware\Vanta.Hardware.psd1') -Force
    Import-Module (Join-Path $script:VantaTestModulesRoot 'Vanta.Toggles\Vanta.Toggles.psd1') -Force

    $script:balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $script:vanta = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb'   # um GUID de teste; o Vanta real usa o que o Windows escolhe
    $script:custom = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    $script:powerCfg = 'C:\Windows\System32\powercfg.exe'

    $togglesRoot = Join-Path $script:VantaTestRepoRoot 'package\Executables\VantaModules\Toggles'
    $script:PowerSaving = Get-VantaToggleDefinition -Name PowerSaving -TogglesRoot $togglesRoot
    $script:Bluetooth = Get-VantaToggleDefinition -Name Bluetooth -TogglesRoot $togglesRoot
    $script:PowerTweakScript = Join-Path $script:VantaTestScriptsRoot 'Tweaks\scripts\set-power-settings.ps1'

    function New-ToggleContext {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$State,
            [bool]$Silent = $true
        )

        return [pscustomobject]@{
            Name           = $Name
            State          = $State
            StateValue     = $null
            Silent         = $Silent
            StateRoot      = 'HKCU:\Software\VantaRewriteTest\HardwareCompanions'
            OperationsPath = Join-Path $TestDrive 'Operations'
        }
    }

    # Runs one companion function exactly as the engine does (dot-sourced into the
    # module scope under strict mode), so module-scoped mocks apply to it.
    function Invoke-CompanionFunction {
        param(
            [Parameter(Mandatory = $true)]$Definition,
            [Parameter(Mandatory = $true)][string]$FunctionName,
            [Parameter(Mandatory = $true)]$Toggle
        )

        InModuleScope Vanta.Toggles {
            Invoke-VantaToggleFunction -Definition $d -FunctionName $f -Toggle $t -Label 'test'
        } -Parameters @{ d = $Definition; f = $FunctionName; t = $Toggle }
    }

    # Runs the private power-scheme core inside the module so module-scoped mocks apply.
    function Invoke-PowerSavingCore {
        param([Parameter(Mandatory = $true)][string]$Mode)

        InModuleScope Vanta.Hardware {
            Invoke-VantaPowerSavingState -RequestedMode $m -PowerCfgPath $p
        } -Parameters @{ m = $Mode; p = $script:powerCfg }
    }

    function New-PnpDevice {
        param(
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FriendlyName,
            [Parameter(Mandatory = $true)][string]$InstanceId
        )

        return [pscustomobject]@{ FriendlyName = $FriendlyName; InstanceId = $InstanceId }
    }
}

Describe 'Vanta power-saving state' {
    BeforeEach {
        $script:newPlan = 'bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb'
        $script:ownRecorded = $null
        $script:ownProven = $false
        $script:activeQueue = New-Object 'Collections.Generic.Queue[string]'
        Mock Get-VantaActivePowerScheme -ModuleName Vanta.Hardware { $script:activeQueue.Dequeue() }
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware { @($script:balanced, $script:custom) }
        Mock Get-VantaPreviousPowerScheme -ModuleName Vanta.Hardware { $null }
        Mock Save-VantaPreviousPowerScheme -ModuleName Vanta.Hardware { $SchemeGuid }
        Mock Clear-VantaPreviousPowerScheme -ModuleName Vanta.Hardware
        Mock Get-VantaOwnPowerScheme -ModuleName Vanta.Hardware { $script:ownRecorded }
        Mock Test-VantaOwnPowerScheme -ModuleName Vanta.Hardware { $script:ownProven }
        Mock Save-VantaOwnPowerScheme -ModuleName Vanta.Hardware { $script:ownRecorded = $SchemeGuid }
        Mock Clear-VantaOwnPowerScheme -ModuleName Vanta.Hardware { $script:ownRecorded = $null }
        # powercfg falso: /duplicatescheme imprime o GUID que o Windows escolheu
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware {
            if ($ArgumentList[0] -ceq '/duplicatescheme') { return @("Power Scheme GUID: $script:newPlan  (copy)") }
            if ($ArgumentList[0] -ceq '/query') { return @('  Current AC Power Setting Index: 0x0000012c', '  Current DC Power Setting Index: 0x000000b4') }
            @()
        }
    }

    It 'creates the Vanta plan as a copy of the active plan with a Windows-chosen GUID, records it and applies only the three reviewed AC settings' {
        $script:activeQueue.Enqueue($script:custom)
        $script:activeQueue.Enqueue($script:newPlan)

        Invoke-PowerSavingCore -Mode Vanta

        Should -Invoke Save-VantaPreviousPowerScheme -ModuleName Vanta.Hardware -Times 1 -Exactly `
            -ParameterFilter { $SchemeGuid -ceq $script:custom }
        # sem GUID de destino: nunca o GUID fixo antigo
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/duplicatescheme' -and $ArgumentList.Count -eq 2 -and
                $ArgumentList[1] -ceq $script:custom
        }
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter {
            $ArgumentList -contains '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke Save-VantaOwnPowerScheme -ModuleName Vanta.Hardware -Times 1 -Exactly `
            -ParameterFilter { $SchemeGuid -ceq $script:newPlan }
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 3 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/setacvalueindex' -and $ArgumentList[1] -ceq $script:newPlan
        }
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/setactive' -and $ArgumentList[1] -ceq $script:newPlan
        }
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/delete'
        }
    }

    It 'never deletes a plan it cannot prove it created, even one holding the old fixed GUID (Atlas)' {
        $atlas = '11111111-1111-1111-1111-111111111111'
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware { @($script:balanced, $script:custom, '11111111-1111-1111-1111-111111111111') }
        $script:ownRecorded = $null     # o Vanta nunca registrou esse GUID
        $script:activeQueue.Enqueue($script:custom)
        $script:activeQueue.Enqueue($script:newPlan)

        Invoke-PowerSavingCore -Mode Vanta
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -ceq '/delete' }

        $script:ownRecorded = $atlas    # registrado, mas sem o nome do Vanta no plano: sem prova
        $script:ownProven = $false
        $script:activeQueue.Enqueue($script:balanced)
        Invoke-PowerSavingCore -Mode Default
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -ceq '/delete' }
        Should -Invoke Clear-VantaOwnPowerScheme -ModuleName Vanta.Hardware -Times 1 -Exactly
    }

    It 'reapplies on top of the active proven Vanta plan: prepares and checks the copy first, activates it and only then removes the old plan' {
        $script:own = 'cccccccc-2222-4222-8222-cccccccccccc'
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware { @($script:balanced, $script:custom, $script:own) }
        Mock Get-VantaPreviousPowerScheme -ModuleName Vanta.Hardware { $script:custom }
        $script:ownRecorded = $script:own
        $script:ownProven = $true
        $script:activeQueue.Enqueue($script:own)
        $script:activeQueue.Enqueue($script:newPlan)
        $script:calls = New-Object Collections.Generic.List[string]
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware {
            $script:calls.Add(($ArgumentList -join ' '))
            if ($ArgumentList[0] -ceq '/duplicatescheme') { return @("Power Scheme GUID: $script:newPlan  (copy)") }
            if ($ArgumentList[0] -ceq '/query') { return @('  Current AC Power Setting Index: 0x0000012c', '  Current DC Power Setting Index: 0x000000b4') }
            @()
        }

        Invoke-PowerSavingCore -Mode Vanta

        # a base é o plano ATIVO (o do Vanta, com os tempos do usuário), nunca o plano anterior guardado
        $script:calls | Should -Contain "/duplicatescheme $script:own"
        $script:calls | Should -Not -Contain "/setactive $script:custom"
        $script:calls | Should -Not -Contain "/setactive $script:balanced"
        Should -Invoke Save-VantaPreviousPowerScheme -ModuleName Vanta.Hardware -Times 0 -Exactly
        $order = @($script:calls | ForEach-Object { ($_ -split ' ')[0] })
        $dup = $order.IndexOf('/duplicatescheme'); $act = $order.IndexOf('/setactive'); $del = $order.IndexOf('/delete')
        $dup | Should -BeLessThan $act
        $act | Should -BeLessThan $del
        $script:calls | Should -Contain "/setactive $script:newPlan"
        $script:calls | Should -Contain "/delete $script:own"
        @($script:calls | Where-Object { $_ -like '/query*' }).Count | Should -Be 4   # 2 ajustes x (origem, cópia); AC e DC vêm na mesma leitura
        $script:ownRecorded | Should -Be $script:newPlan
    }

    It 'keeps the active plan and the old Vanta plan untouched when the copy cannot be created' {
        $script:own = 'cccccccc-2222-4222-8222-cccccccccccc'
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware { @($script:balanced, $script:custom, $script:own) }
        $script:ownRecorded = $script:own
        $script:ownProven = $true
        $script:activeQueue.Enqueue($script:own)
        $script:calls = New-Object Collections.Generic.List[string]
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware {
            $script:calls.Add(($ArgumentList -join ' '))
            if ($ArgumentList[0] -ceq '/duplicatescheme') { throw 'duplicate failed' }
            @()
        }

        { Invoke-PowerSavingCore -Mode Vanta } | Should -Throw '*duplicate failed*'

        @($script:calls | Where-Object { $_ -like '/setactive*' -or $_ -like '/delete*' }).Count | Should -Be 0
        $script:ownRecorded | Should -Be $script:own
    }

    It 'aborts before activating when the copy does not have the same four timeouts' {
        $script:own = 'cccccccc-2222-4222-8222-cccccccccccc'
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware { @($script:balanced, $script:custom, $script:own) }
        $script:ownRecorded = $script:own
        $script:ownProven = $true
        $script:activeQueue.Enqueue($script:own)
        $script:calls = New-Object Collections.Generic.List[string]
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware {
            $script:calls.Add(($ArgumentList -join ' '))
            if ($ArgumentList[0] -ceq '/duplicatescheme') { return @("Power Scheme GUID: $script:newPlan  (copy)") }
            if ($ArgumentList[0] -ceq '/query') {
                # a cópia perdeu a tela de bateria que o usuário tinha no plano ativo
                $dc = if ($ArgumentList[1] -ceq $script:newPlan) { '0x00000000' } else { '0x000000b4' }
                return @('  Current AC Power Setting Index: 0x0000012c', "  Current DC Power Setting Index: $dc")
            }
            @()
        }

        { Invoke-PowerSavingCore -Mode Vanta } | Should -Throw '*differs from the active one*'

        @($script:calls | Where-Object { $_ -like '/setactive*' }).Count | Should -Be 0
        $script:calls | Should -Contain "/delete $script:newPlan"
        $script:calls | Should -Not -Contain "/delete $script:own"
        $script:ownRecorded | Should -Be $script:own
    }

    It 'discards only the plan it just created and records nothing when a step fails' {
        $script:activeQueue.Enqueue($script:custom)
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware {
            if ($ArgumentList[0] -ceq '/duplicatescheme') { return @("Power Scheme GUID: $script:newPlan  (copy)") }
            if ($ArgumentList[0] -ceq '/query') { return @('  Current AC Power Setting Index: 0x0000012c', '  Current DC Power Setting Index: 0x000000b4') }
            if ($ArgumentList[0] -ceq '/setacvalueindex') { throw 'powercfg failed' }
            @()
        }

        { Invoke-PowerSavingCore -Mode Vanta } | Should -Throw '*powercfg failed*'

        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/delete' -and $ArgumentList[1] -ceq $script:newPlan
        }
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/setactive'
        }
        $script:ownRecorded | Should -BeNullOrEmpty
    }

    It 'restores an installed saved plan and then removes only the proven Vanta plan' {
        $script:own = 'cccccccc-2222-4222-8222-cccccccccccc'
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware {
            @($script:balanced, $script:custom, $script:own)
        }
        Mock Get-VantaPreviousPowerScheme -ModuleName Vanta.Hardware { $script:custom }
        $script:ownRecorded = $script:own
        $script:ownProven = $true
        $script:activeQueue.Enqueue($script:custom)

        Invoke-PowerSavingCore -Mode Default

        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/setactive' -and
                $ArgumentList[1] -ceq $script:custom
        }
        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/delete' -and
                $ArgumentList[1] -ceq $script:own
        }
        Should -Invoke Clear-VantaPreviousPowerScheme -ModuleName Vanta.Hardware -Times 1 -Exactly `
            -ParameterFilter { $ExpectedSchemeGuid -ceq $script:custom }
        Should -Invoke Clear-VantaOwnPowerScheme -ModuleName Vanta.Hardware -Times 1 -Exactly
    }

    It 'falls back to Balanced when the saved plan is no longer installed' {
        Mock Get-VantaPreviousPowerScheme -ModuleName Vanta.Hardware { 'dddddddd-3333-4333-8333-dddddddddddd' }
        $script:activeQueue.Enqueue($script:balanced)

        Invoke-PowerSavingCore -Mode Default

        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $ArgumentList[0] -ceq '/setactive' -and
                $ArgumentList[1] -ceq $script:balanced
        }
    }

    It 'keeps the saved plan when the final active-plan check fails' {
        Mock Get-VantaPreviousPowerScheme -ModuleName Vanta.Hardware { $script:custom }
        $script:activeQueue.Enqueue($script:balanced)

        { Invoke-PowerSavingCore -Mode Default } | Should -Throw '*expected*'

        Should -Invoke Clear-VantaPreviousPowerScheme -ModuleName Vanta.Hardware -Times 0 -Exactly
    }

    It 'fails when the Windows Balanced scheme is missing' {
        Mock Get-VantaPowerSchemeInventory -ModuleName Vanta.Hardware { @($script:custom) }

        { Invoke-PowerSavingCore -Mode Vanta } | Should -Throw '*Balanced power scheme is not installed*'

        Should -Invoke Invoke-VantaPowerCfg -ModuleName Vanta.Hardware -Times 0 -Exactly
    }
}

Describe 'Vanta plan ownership proof' {
    It 'needs the recorded GUID AND the Vanta plan name in the plan list' {
        $own = 'cccccccc-2222-4222-8222-cccccccccccc'
        Mock Get-VantaOwnPowerScheme -ModuleName Vanta.Hardware { 'cccccccc-2222-4222-8222-cccccccccccc' }
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware {
            @('Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)',
                'Power Scheme GUID: cccccccc-2222-4222-8222-cccccccccccc  (Vanta Power Scheme) *',
                'Power Scheme GUID: 11111111-1111-1111-1111-111111111111  (Atlas Power Scheme)')
        }
        InModuleScope Vanta.Hardware { Test-VantaOwnPowerScheme -PowerCfgPath $p -SchemeGuid $g } -Parameters @{ p = $script:powerCfg; g = $own } | Should -BeTrue
        # o plano do Atlas no GUID antigo nunca é nosso: não está registrado
        InModuleScope Vanta.Hardware { Test-VantaOwnPowerScheme -PowerCfgPath $p -SchemeGuid $g } -Parameters @{ p = $script:powerCfg; g = '11111111-1111-1111-1111-111111111111' } | Should -BeFalse
        # registrado, mas o plano agora tem outro nome
        Mock Invoke-VantaPowerCfg -ModuleName Vanta.Hardware { @('Power Scheme GUID: cccccccc-2222-4222-8222-cccccccccccc  (Meu plano)') }
        InModuleScope Vanta.Hardware { Test-VantaOwnPowerScheme -PowerCfgPath $p -SchemeGuid $g } -Parameters @{ p = $script:powerCfg; g = $own } | Should -BeFalse
    }
}

Describe 'powercfg helpers' {
    It 'propagates a nonzero powercfg exit code' {
        $commandProcessor = Join-Path -Path ([Environment]::SystemDirectory) `
            -ChildPath 'cmd.exe'

        {
            InModuleScope Vanta.Hardware {
                Invoke-VantaPowerCfg -FilePath $c -ArgumentList @('/d', '/c', 'exit 7')
            } -Parameters @{ c = $commandProcessor }
        } | Should -Throw "*exit code '7'*"
    }

    It 'reports the exit code and powercfg message when the engine stops on errors' {
        $commandProcessor = Join-Path -Path ([Environment]::SystemDirectory) `
            -ChildPath 'cmd.exe'

        {
            InModuleScope Vanta.Hardware {
                $ErrorActionPreference = 'Stop'
                Invoke-VantaPowerCfg -FilePath $c -ArgumentList @('/d', '/c', 'echo scheme exists 1>&2 & exit 1')
            } -Parameters @{ c = $commandProcessor }
        } | Should -Throw "*exit code '1'*scheme exists*"
    }

    It 'parses scheme GUIDs independently of localized powercfg labels' {
        $result = InModuleScope Vanta.Hardware {
            Get-VantaPowerSchemeGuidFromOutput -Output @(
                ''
                "Localized label: $b"
                "Another label: $c"
            )
        } -Parameters @{ b = $script:balanced; c = $script:custom }

        $result | Should -Be @($script:balanced, $script:custom)
    }
}

Describe 'Set-VantaPowerSavingState' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Hardware
        Mock Write-VantaStep -ModuleName Vanta.Hardware
        Mock Assert-VantaPrivilege -ModuleName Vanta.Hardware
        Mock Invoke-VantaPowerSavingState -ModuleName Vanta.Hardware
    }

    It 'requires Administrator rights before any powercfg work' {
        Mock Assert-VantaPrivilege -ModuleName Vanta.Hardware { throw '[privilege] This operation requires Administrator rights.' }

        { Set-VantaPowerSavingState -Mode Vanta -Silent } | Should -Throw '*requires Administrator*'

        Should -Invoke Invoke-VantaPowerSavingState -ModuleName Vanta.Hardware -Times 0 -Exactly
    }

    It 'applies the requested mode through the exact System32 powercfg and reports progress unless silent' {
        Set-VantaPowerSavingState -Mode Default

        $expected = [IO.Path]::Combine([Environment]::SystemDirectory, 'powercfg.exe')
        Should -Invoke Invoke-VantaPowerSavingState -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $RequestedMode -ceq 'Default' -and $PowerCfgPath -eq $expected
        }
        Should -Invoke Write-VantaStep -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Text -like 'Restoring the previous power plan*'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Message -like "*'Default'*"
        }

        Set-VantaPowerSavingState -Mode Vanta -Silent

        Should -Invoke Invoke-VantaPowerSavingState -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $RequestedMode -ceq 'Vanta'
        }
        Should -Invoke Write-VantaStep -ModuleName Vanta.Hardware -Times 1 -Exactly
    }

    It 'releases the transaction lock when the operation fails' {
        Mock Invoke-VantaPowerSavingState -ModuleName Vanta.Hardware { throw 'simulated powercfg failure' }

        { Set-VantaPowerSavingState -Mode Vanta -Silent } | Should -Throw '*simulated powercfg failure*'

        # The owning thread could take the mutex again even if it was never released,
        # so probe from another thread.
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.ThreadOptions = [Management.Automation.Runspaces.PSThreadOptions]::UseNewThread
        $runspace.Open()
        $probe = [powershell]::Create()
        $probe.Runspace = $runspace
        try {
            $null = $probe.AddScript({
                    $mutex = New-Object Threading.Mutex($false, 'Global\Vanta.PowerSaving.Transaction.v1')
                    try {
                        $acquired = $mutex.WaitOne(0)
                        if ($acquired) { $mutex.ReleaseMutex() }
                        $acquired
                    }
                    finally { $mutex.Dispose() }
                })
            @($probe.Invoke()) | Should -Be @($true)
        }
        finally {
            $probe.Dispose()
            $runspace.Dispose()
        }
    }
}

Describe 'Set-VantaDeviceState' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Hardware
        Mock Write-VantaSuccess -ModuleName Vanta.Hardware
        Mock Write-VantaNote -ModuleName Vanta.Hardware
        Mock Import-VantaPnpDeviceModule -ModuleName Vanta.Hardware
        Mock Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware {
            @(
                (New-PnpDevice -FriendlyName 'Intel Bluetooth Adapter' -InstanceId 'USB\VID_8087&PID_0026\BT1')
                (New-PnpDevice -FriendlyName 'Bluetooth Device (RFCOMM)' -InstanceId 'BTH\MS_RFCOMM\BT2')
                (New-PnpDevice -FriendlyName 'USB Root Hub' -InstanceId 'USB\ROOT_HUB30\HUB1')
                (New-PnpDevice -FriendlyName '' -InstanceId 'ACPI\NAMELESS\1')
            )
        }
        Mock Set-VantaPnpDeviceState -ModuleName Vanta.Hardware { @(0) }
        Mock Get-VantaPnpDeviceParentId -ModuleName Vanta.Hardware { $null }
        Mock Start-Sleep -ModuleName Vanta.Hardware
    }

    It 'disables every present device matching a pattern and nothing else' {
        Set-VantaDeviceState -State Disable -Devices '*Bluetooth*' -Silent

        Should -Invoke Import-VantaPnpDeviceModule -ModuleName Vanta.Hardware -Times 1 -Exactly
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 2 -Exactly
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $InstanceId -ceq 'USB\VID_8087&PID_0026\BT1' -and $State -ceq 'Disable'
        }
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $InstanceId -ceq 'BTH\MS_RFCOMM\BT2' -and $State -ceq 'Disable'
        }
        Should -Invoke Write-VantaSuccess -ModuleName Vanta.Hardware -Times 0 -Exactly
        Should -Invoke Write-VantaNote -ModuleName Vanta.Hardware -Times 0 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Message -like 'Disabled 2 matched device(s)*'
        }
    }

    It 'enables with several patterns and lists the devices when not silent' {
        Set-VantaDeviceState -State Enable -Devices @('*RFCOMM*', 'USB Root*')

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 2 -Exactly -ParameterFilter {
            $State -ceq 'Enable'
        }
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter {
            $InstanceId -like '*BT1'
        }
        Should -Invoke Write-VantaSuccess -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Text -ceq 'Enabled 2 device(s):'
        }
        Should -Invoke Write-VantaNote -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Text -contains '  - USB Root Hub'
        }
    }

    It 'treats whatever the provider echoes as success' {
        # The inbox cmdlets echo the device object at most, such as the RFCOMM entity
        # below, which must never be read as an exit code.
        Mock Set-VantaPnpDeviceState -ModuleName Vanta.Hardware {
            New-PnpDevice -FriendlyName 'Bluetooth Device (RFCOMM Protocol TDI)' -InstanceId 'BTH\MS_RFCOMM\9&123F897D&0&0'
        }
        { Set-VantaDeviceState -State Enable -Devices '*Bluetooth*' -Silent } | Should -Not -Throw
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 2 -Exactly
    }

    It 'fails without a match unless AllowNoMatch is given' {
        { Set-VantaDeviceState -State Disable -Devices '*Thunderbolt*' -Silent } |
            Should -Throw '*No present devices matched: *Thunderbolt*'

        { Set-VantaDeviceState -State Disable -Devices '*Thunderbolt*' -Silent -AllowNoMatch } |
            Should -Not -Throw

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 0 -Exactly
    }

    It 'never matches a device with a blank friendly name' {
        Set-VantaDeviceState -State Disable -Devices '*' -Silent

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 3 -Exactly
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter {
            $InstanceId -like 'ACPI*'
        }
    }

    It 'reports a provider failure and stops at that device' {
        Mock Set-VantaPnpDeviceState -ModuleName Vanta.Hardware { throw 'Generic failure (5)' }

        { Set-VantaDeviceState -State Disable -Devices '*Bluetooth*' -Silent } |
            Should -Throw "*Disabling device 'Intel Bluetooth Adapter'*failed: Generic failure (5)*"

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 1 -Exactly
    }

    It 'reports an enumeration failure instead of treating it as no match' {
        Mock Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware { throw 'RPC server unavailable' }

        { Set-VantaDeviceState -State Disable -Devices '*Bluetooth*' -Silent -AllowNoMatch } |
            Should -Throw '*RPC server unavailable*'
    }

    It 'rejects blank or oversized patterns before enumerating' {
        { Set-VantaDeviceState -State Disable -Devices @('*Bluetooth*', '   ') -Silent } |
            Should -Throw '*nonempty and at most 256 characters*'
        { Set-VantaDeviceState -State Disable -Devices ('a' * 257) -Silent } |
            Should -Throw '*nonempty and at most 256 characters*'
        { Set-VantaDeviceState -State Disable -Devices @() -Silent } | Should -Throw

        Should -Invoke Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware -Times 0 -Exactly
    }

    It 'leaves matched descendants to a matched ancestor when disabling' {
        Mock Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware {
            @(
                (New-PnpDevice -FriendlyName 'USB Root Hub' -InstanceId 'USB\ROOT_HUB30\HUB1')
                (New-PnpDevice -FriendlyName 'Intel Bluetooth Adapter' -InstanceId 'USB\VID_8087&PID_0026\BT1')
                (New-PnpDevice -FriendlyName 'Microsoft Bluetooth LE Enumerator' -InstanceId 'BTH\MS_BTHLE\BT2')
                (New-PnpDevice -FriendlyName 'Headphones' -InstanceId 'BTHLE\DEV_A\BT3')
                (New-PnpDevice -FriendlyName 'Bluetooth LE Generic Attribute Service' -InstanceId 'BTHLEDEVICE\GATT\BT4')
            )
        }
        # The paired headphones don't match, so the GATT service's matched ancestor is
        # two levels up. Windows reports parent IDs in their own case.
        Mock Get-VantaPnpDeviceParentId -ModuleName Vanta.Hardware {
            switch -CaseSensitive ([string]$Device.InstanceId) {
                'USB\VID_8087&PID_0026\BT1' { 'USB\ROOT_HUB30\HUB1' }
                'BTH\MS_BTHLE\BT2' { 'USB\VID_8087&PID_0026\bt1' }
                'BTHLE\DEV_A\BT3' { 'BTH\MS_BTHLE\BT2' }
                'BTHLEDEVICE\GATT\BT4' { 'BTHLE\DEV_A\BT3' }
                default { $null }
            }
        }

        Set-VantaDeviceState -State Disable -Devices '*Bluetooth*' -Silent

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 1 -Exactly
        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $InstanceId -ceq 'USB\VID_8087&PID_0026\BT1' -and $State -ceq 'Disable'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Message -ceq 'Left 2 matched device(s) to a matched parent: Microsoft Bluetooth LE Enumerator, Bluetooth LE Generic Attribute Service.'
        }
    }

    It 'still disables every match when the device tree cannot be read' {
        Mock Get-VantaPnpDeviceParentId -ModuleName Vanta.Hardware { throw 'provider unavailable' }

        Set-VantaDeviceState -State Disable -Devices '*Bluetooth*' -Silent

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 2 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Level -ceq 'Warning' -and $Message -like "Couldn't read the device tree*provider unavailable*"
        }
    }

    It 'enables a matched child that reappears disabled once its parent starts' {
        # Code 22 is a device's own disable flag, which a child keeps while its parent is off.
        $script:deviceCodes = [ordered]@{ 'USB\VID_8087&PID_0026\BT1' = 22 }
        Mock Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware {
            foreach ($id in @($script:deviceCodes.Keys)) {
                $name = if ($id -like 'BTH\*') { 'Microsoft Bluetooth Enumerator' } else { 'Intel Bluetooth Adapter' }
                [pscustomobject]@{ FriendlyName = $name; InstanceId = $id; ConfigManagerErrorCode = $script:deviceCodes[$id] }
            }
        }
        Mock Set-VantaPnpDeviceState -ModuleName Vanta.Hardware {
            $script:deviceCodes[$InstanceId] = 0
            if ($InstanceId -ceq 'USB\VID_8087&PID_0026\BT1') {
                $script:deviceCodes['BTH\MS_BTHBRB\BT2'] = 22
            }
        }

        Set-VantaDeviceState -State Enable -Devices '*Bluetooth*' -Silent

        Should -Invoke Set-VantaPnpDeviceState -ModuleName Vanta.Hardware -Times 2 -Exactly -ParameterFilter {
            $State -ceq 'Enable'
        }
        $script:deviceCodes['BTH\MS_BTHBRB\BT2'] | Should -Be 0
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Message -ceq 'Enabled 2 matched device(s): Intel Bluetooth Adapter, Microsoft Bluetooth Enumerator.'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter { $Level -ceq 'Warning' }
    }

    It 'keeps polling until a slow parent enumerates its disabled child' {
        # The radio's child appears only on the third poll after the radio is enabled.
        $script:enumerations = 0
        $script:deviceCodes = [ordered]@{ 'USB\VID_8087&PID_0026\BT1' = 22 }
        Mock Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware {
            $script:enumerations++
            if ($script:enumerations -eq 4) {
                $script:deviceCodes['BTH\MS_BTHBRB\BT2'] = 22
            }
            foreach ($id in @($script:deviceCodes.Keys)) {
                $name = if ($id -like 'BTH\*') { 'Microsoft Bluetooth Enumerator' } else { 'Intel Bluetooth Adapter' }
                [pscustomobject]@{ FriendlyName = $name; InstanceId = $id; ConfigManagerErrorCode = $script:deviceCodes[$id] }
            }
        }
        Mock Set-VantaPnpDeviceState -ModuleName Vanta.Hardware { $script:deviceCodes[$InstanceId] = 0 }

        Set-VantaDeviceState -State Enable -Devices '*Bluetooth*' -Silent

        $script:deviceCodes['BTH\MS_BTHBRB\BT2'] | Should -Be 0
        Should -Invoke Start-Sleep -ModuleName Vanta.Hardware -Times 4 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Message -ceq 'Enabled 2 matched device(s): Intel Bluetooth Adapter, Microsoft Bluetooth Enumerator.'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 0 -Exactly -ParameterFilter { $Level -ceq 'Warning' }
    }

    It 'warns naming a matched device that stays disabled after enabling' {
        Mock Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware {
            [pscustomobject]@{ FriendlyName = 'Intel Bluetooth Adapter'; InstanceId = 'USB\VID_8087&PID_0026\BT1'; ConfigManagerErrorCode = 22 }
        }

        { Set-VantaDeviceState -State Enable -Devices '*Bluetooth*' -Silent } | Should -Not -Throw

        Should -Invoke Start-Sleep -ModuleName Vanta.Hardware -Times 5 -Exactly
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Message -like 'No other matched devices appeared within 10 seconds of enabling.*'
        }
        Should -Invoke Write-VantaLog -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $Level -ceq 'Warning' -and
            $Message -ceq 'Matched device(s) still disabled after enabling: Intel Bluetooth Adapter (USB\VID_8087&PID_0026\BT1).'
        }
    }

    It 'does not wait for children when no matched device was disabled' {
        Set-VantaDeviceState -State Enable -Devices '*Bluetooth*' -Silent

        Should -Invoke Start-Sleep -ModuleName Vanta.Hardware -Times 0 -Exactly
        Should -Invoke Get-VantaPresentPnpDevice -ModuleName Vanta.Hardware -Times 1 -Exactly
    }
}

Describe 'Get-VantaPnpDeviceParentId' {
    BeforeEach {
        # Invoke-CimMethod binds -InputObject only to a CIM instance. The PnpDevice type
        # data adds InstanceId once a test has loaded that module, and only then.
        $script:radio = New-CimInstance -ClassName Win32_PnPEntity -Namespace root/cimv2 -ClientOnly `
            -Property @{ DeviceID = 'USB\VID_8087&PID_0026\BT1' }
        if ($null -eq $script:radio.PSObject.Properties['InstanceId']) {
            Add-Member -InputObject $script:radio -NotePropertyName InstanceId -NotePropertyValue $script:radio.DeviceID
        }
    }

    It 'returns the parent instance ID that GetDeviceProperties reports' {
        Mock Invoke-CimMethod -ModuleName Vanta.Hardware {
            [pscustomobject]@{
                ReturnValue      = 0
                deviceProperties = @(New-CimInstance -ClassName Win32_PnPDevicePropertyString -Namespace root/cimv2 -ClientOnly `
                        -Property @{ KeyName = 'DEVPKEY_Device_Parent'; Data = 'USB\ROOT_HUB30\HUB1' })
            }
        }

        InModuleScope Vanta.Hardware -Parameters @{ Device = $script:radio } {
            param($Device)
            Get-VantaPnpDeviceParentId -Device $Device
        } | Should -BeExactly 'USB\ROOT_HUB30\HUB1'
        Should -Invoke Invoke-CimMethod -ModuleName Vanta.Hardware -Times 1 -Exactly -ParameterFilter {
            $MethodName -ceq 'GetDeviceProperties' -and
            @($Arguments['devicePropertyKeys']) -ccontains 'DEVPKEY_Device_Parent'
        }
    }

    It 'returns nothing for the root device, whose property has no Data' {
        Mock Invoke-CimMethod -ModuleName Vanta.Hardware {
            [pscustomobject]@{
                ReturnValue      = 0
                deviceProperties = @(New-CimInstance -ClassName Win32_PnPDeviceProperty -Namespace root/cimv2 -ClientOnly `
                        -Property @{ KeyName = 'DEVPKEY_Device_Parent' })
            }
        }

        InModuleScope Vanta.Hardware -Parameters @{ Device = $script:radio } {
            param($Device)
            Get-VantaPnpDeviceParentId -Device $Device
        } | Should -BeNullOrEmpty
    }

    It 'reports a failed GetDeviceProperties call' {
        Mock Invoke-CimMethod -ModuleName Vanta.Hardware { [pscustomobject]@{ ReturnValue = 5; deviceProperties = $null } }

        {
            InModuleScope Vanta.Hardware -Parameters @{ Device = $script:radio } {
                param($Device)
                Get-VantaPnpDeviceParentId -Device $Device
            }
        } | Should -Throw "Reading the parent of device 'USB\VID_8087&PID_0026\BT1' returned 5."
    }
}

Describe 'Hardware toggle companions' {
    BeforeEach {
        Mock Write-VantaLog -ModuleName Vanta.Toggles
        Mock Write-VantaSuccess -ModuleName Vanta.Toggles
        Mock Write-VantaStep -ModuleName Vanta.Toggles
        Mock Import-VantaModule -ModuleName Vanta.Toggles
        Mock Get-VantaToggleState -ModuleName Vanta.Toggles { $null }
    }

    It 'PowerSaving maps both recorded states onto the power-saving modes' {
        Mock Set-VantaPowerSavingState -ModuleName Vanta.Toggles

        $definition = $script:PowerSaving
        foreach ($stateName in @('Disable', 'Enable')) {
            $definition.States[$stateName]['MachineAction'] | Should -BeExactly 'Invoke-VantaPowerSavingToggle'
        }

        Invoke-CompanionFunction -Definition $definition -FunctionName 'Invoke-VantaPowerSavingToggle' `
            -Toggle (New-ToggleContext -Name 'PowerSaving' -State 'Disable' -Silent $true)
        Invoke-CompanionFunction -Definition $definition -FunctionName 'Invoke-VantaPowerSavingToggle' `
            -Toggle (New-ToggleContext -Name 'PowerSaving' -State 'Enable' -Silent $false)

        Should -Invoke Set-VantaPowerSavingState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Mode -ceq 'Vanta' -and $Silent
        }
        Should -Invoke Set-VantaPowerSavingState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Mode -ceq 'Default' -and -not $Silent
        }
        Should -Invoke Import-VantaModule -ModuleName Vanta.Toggles -Times 2 -Exactly -ParameterFilter { $Name -ceq 'Vanta.Hardware' }
        Should -Invoke Write-VantaSuccess -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $Text -like 'The previous power plan*'
        }
    }

    It 'Bluetooth disables and enables the present Bluetooth devices tolerating absence' {
        Mock Set-VantaDeviceState -ModuleName Vanta.Toggles

        $definition = $script:Bluetooth
        $definition.States['Disable']['MachineAction'] | Should -BeExactly 'Disable-VantaBluetoothDevices'
        $definition.States['Enable']['MachineAction'] | Should -BeExactly 'Enable-VantaBluetoothDevices'

        Invoke-CompanionFunction -Definition $definition -FunctionName 'Disable-VantaBluetoothDevices' `
            -Toggle (New-ToggleContext -Name 'Bluetooth' -State 'Disable')
        Invoke-CompanionFunction -Definition $definition -FunctionName 'Enable-VantaBluetoothDevices' `
            -Toggle (New-ToggleContext -Name 'Bluetooth' -State 'Enable')

        Should -Invoke Set-VantaDeviceState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -ceq 'Disable' -and @($Devices) -ceq '*Bluetooth*' -and $AllowNoMatch -and $Silent
        }
        Should -Invoke Set-VantaDeviceState -ModuleName Vanta.Toggles -Times 1 -Exactly -ParameterFilter {
            $State -ceq 'Enable' -and @($Devices) -ceq '*Bluetooth*' -and $AllowNoMatch -and $Silent
        }
        Should -Invoke Import-VantaModule -ModuleName Vanta.Toggles -Times 2 -Exactly -ParameterFilter { $Name -ceq 'Vanta.Hardware' }
    }
}

Describe 'set-power-settings install tweak' {
    It 'applies and records the power-saving choice through the toggle engine' {
        Mock Test-VantaOption { $Name -ceq 'disable-power-saving' }
        Mock Import-VantaModule
        Mock Invoke-VantaToggleMachineState

        & $script:PowerTweakScript

        Should -Invoke Import-VantaModule -Times 1 -Exactly -ParameterFilter { $Name -ceq 'Vanta.Toggles' }
        Should -Invoke Invoke-VantaToggleMachineState -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'PowerSaving' -and $State -ceq 'Disable'
        }
    }

    It 'applies and records the hibernation choice through the toggle engine' {
        Mock Test-VantaOption { $Name -cin @('disable-power-saving', 'disable-hibernation') }
        Mock Import-VantaModule
        Mock Invoke-VantaToggleMachineState
        Mock Invoke-VantaToggleNativeCommand

        & $script:PowerTweakScript

        Should -Invoke Invoke-VantaToggleMachineState -Times 1 -Exactly -ParameterFilter {
            $Name -ceq 'Hibernation' -and $State -ceq 'Disable'
        }
        Should -Not -Invoke Invoke-VantaToggleNativeCommand
    }

    It 'selects Balanced through the checked native runner when power saving is kept' {
        # Literal GUIDs: a mock the companion calls resolves $script: in the companion's own scope.
        Mock Test-VantaOption { $false }
        Mock Import-VantaModule
        Mock Invoke-VantaToggleMachineState
        Mock Invoke-VantaToggleNativeCommand {
            if ($PassThru) { [pscustomobject]@{ Output = [string[]]@('Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)') } }
        }

        & $script:PowerTweakScript

        Should -Not -Invoke Invoke-VantaToggleMachineState
        Should -Invoke Invoke-VantaToggleNativeCommand -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -ceq '/setactive 381b4222-f694-41f0-9685-ff5bb260df2e' -and ($AllowedExitCodes -join ',') -ceq '0'
        }
        Should -Invoke Invoke-VantaToggleNativeCommand -Times 1 -Exactly -ParameterFilter {
            ($ArgumentList -join ' ') -ceq '/getactivescheme' -and $PassThru
        }

        Mock Invoke-VantaToggleNativeCommand {
            if ($PassThru) { [pscustomobject]@{ Output = [string[]]@('Power Scheme GUID: 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c  (High performance)') } }
        }
        { & $script:PowerTweakScript } | Should -Throw '*Balanced power scheme did not become the active scheme*'
    }
}
