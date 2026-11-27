# Vanta.Network domain: the File Sharing machine state shared by the fresh install
# and the FileSharing toggle. Enable restores the adapter bindings, NetBIOS, the NetBT
# driver and Network Discovery; Disable removes them, forces Public network profiles,
# disables the sharing firewall groups and removes the Sharing context menu.

# Client for Microsoft Networks, File and Printer Sharing for Microsoft Networks, and the
# Link-Layer Topology Discovery mapper I/O driver and responder.
$script:VantaFileSharingBindingComponents = @('ms_msclient', 'ms_server', 'ms_lltdio', 'ms_rspndr')
$script:VantaFileSharingNetBtInterfacesRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces'
# The Sharing shell extension behind the 'Give access to' context menu.
$script:VantaFileSharingContextMenuClsid = '{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}'
$script:VantaFileSharingContextMenuKeys = @(
    'Registry::HKEY_CLASSES_ROOT\*\shellex\ContextMenuHandlers\Sharing'
    'Registry::HKEY_CLASSES_ROOT\Directory\Background\shellex\ContextMenuHandlers\Sharing'
    'Registry::HKEY_CLASSES_ROOT\Directory\shellex\ContextMenuHandlers\Sharing'
    'Registry::HKEY_CLASSES_ROOT\Drive\shellex\ContextMenuHandlers\Sharing'
    'Registry::HKEY_CLASSES_ROOT\LibraryFolder\background\shellex\ContextMenuHandlers\Sharing'
    'Registry::HKEY_CLASSES_ROOT\UserLibraryFolder\shellex\ContextMenuHandlers\Sharing'
)
$script:VantaFileSharingMachineContextMenuKeys = @(
    'HKLM:\SOFTWARE\Classes\*\shellex\ContextMenuHandlers\Sharing'
    'HKLM:\SOFTWARE\Classes\Directory\Background\shellex\ContextMenuHandlers\Sharing'
    'HKLM:\SOFTWARE\Classes\Directory\shellex\ContextMenuHandlers\Sharing'
    'HKLM:\SOFTWARE\Classes\Drive\shellex\ContextMenuHandlers\Sharing'
    'HKLM:\SOFTWARE\Classes\LibraryFolder\background\shellex\ContextMenuHandlers\Sharing'
    'HKLM:\SOFTWARE\Classes\UserLibraryFolder\shellex\ContextMenuHandlers\Sharing'
)

function Get-VantaFileSharingFirewallRule {
    <#
    .SYNOPSIS
        Returns the Private-profile rules of the File and Printer Sharing and Network
        Discovery groups.
    #>
    # The group resource strings identify the two groups in any display language; the
    # English display names cover rules created without them.
    @(Get-NetFirewallRule -ErrorAction Stop | Where-Object {
            ($_.Group -in @('@FirewallAPI.dll,-28502', '@FirewallAPI.dll,-32752') -or
                $_.DisplayGroup -in @('File and Printer Sharing', 'Network Discovery')) -and
            ($_.Profile -like '*Private*' -or [string]$_.Profile -eq 'Any')
        })
}

function Enable-VantaPrivateSharingFirewallRule {
    <#
    .SYNOPSIS
        Enables sharing on Private networks without enabling a disabled rule's
        Public or Domain coverage. Combined-profile rules get a Private-only copy;
        Copy-NetFirewallRule preserves all of the original rule's traffic filters.
    #>
    $rules = @(Get-VantaFileSharingFirewallRule)
    $processed = @{}
    foreach ($rule in $rules) {
        # Copies are reached through their source rule, never copied recursively.
        if ([string]$rule.Name -like 'Vanta-Private-*') { continue }
        if ($processed.ContainsKey([string]$rule.Name)) { continue }
        $target = $rule
        if ([string]$rule.Profile -ne 'Private') {
            # Already-enabled coverage belongs to the user's existing configuration.
            if ([string]$rule.Enabled -in @('True', '1')) { continue }

            $copyName = 'Vanta-Private-' + $rule.Name
            $existing = @($rules | Where-Object { $_.Name -eq $copyName })
            if ($existing.Count -gt 1) {
                throw "Multiple firewall rules use the name '$copyName'."
            }
            if ($existing.Count -eq 1) {
                $target = $existing[0]
                if ($target.Group -ne $rule.Group -or
                    ([string]$target.Profile -ne 'Private' -and
                        [string]$target.Enabled -notin @('False', '0'))) {
                    throw "Firewall rule '$copyName' is not the expected Private sharing rule."
                }
            }
            else {
                # The source is disabled, so copying it cannot temporarily open its
                # other profiles. Narrow the copy before enabling it.
                Copy-NetFirewallRule -InputObject $rule -NewName $copyName `
                    -ErrorAction Stop | Out-Null
                # Copy's PassThru object can still identify the source. Resolve the
                # persisted copy by its new name before making any changes.
                $copy = @(Get-NetFirewallRule -Name $copyName -ErrorAction Stop)
                if ($copy.Count -ne 1 -or $copy[0].Group -ne $rule.Group -or
                    [string]$copy[0].Enabled -notin @('False', '0')) {
                    throw "Could not resolve the disabled copy of firewall rule '$($rule.Name)'."
                }
                $target = $copy[0]
            }
            if ([string]$target.Profile -ne 'Private') {
                # Also finish narrowing a disabled copy left by an interrupted run.
                Set-NetFirewallRule -InputObject $target -Profile Private -Enabled False `
                    -ErrorAction Stop | Out-Null
                $current = @(Get-NetFirewallRule -Name $copyName -ErrorAction Stop)
                if ($current.Count -ne 1 -or [string]$current[0].Profile -ne 'Private' -or
                    [string]$current[0].Enabled -notin @('False', '0')) {
                    throw "Firewall rule '$copyName' did not retain its disabled Private scope."
                }
                $target = $current[0]
            }
        }

        if ($processed.ContainsKey([string]$target.Name)) { continue }
        Enable-NetFirewallRule -InputObject $target -ErrorAction Stop | Out-Null
        $current = @(Get-NetFirewallRule -Name $target.Name -ErrorAction Stop)
        if ($current.Count -ne 1 -or [string]$current[0].Profile -ne 'Private' -or
            [string]$current[0].Enabled -notin @('True', '1')) {
            throw "Firewall rule '$($target.Name)' did not retain its enabled Private scope."
        }
        $processed[[string]$target.Name] = $true
    }
}

function Set-VantaFileSharingAdapterBinding {
    <#
    .SYNOPSIS
        Enables or disables the managed adapter binding components on every adapter and
        verifies that no binding was left in the opposite state.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $components = $script:VantaFileSharingBindingComponents
    foreach ($binding in @(Get-NetAdapterBinding -Name '*' -ComponentID $components -ErrorAction Stop)) {
        if ([bool]$binding.Enabled -eq $Enabled) {
            continue
        }
        if ($Enabled) {
            Enable-NetAdapterBinding -Name ([string]$binding.Name) `
                -ComponentID ([string]$binding.ComponentID) -Confirm:$false `
                -ErrorAction Stop | Out-Null
        }
        else {
            Disable-NetAdapterBinding -Name ([string]$binding.Name) `
                -ComponentID ([string]$binding.ComponentID) -Confirm:$false `
                -ErrorAction Stop | Out-Null
        }
    }

    $remaining = @(Get-NetAdapterBinding -Name '*' -ComponentID $components -ErrorAction Stop |
            Where-Object { [bool]$_.Enabled -ne $Enabled })
    if ($remaining.Count -ne 0) {
        $stateText = if ($Enabled) { 'enable left a managed adapter binding disabled' }
        else { 'disable left a managed adapter binding enabled' }
        throw "File Sharing $stateText."
    }
}

function Set-VantaFileSharingNetBiosOption {
    <#
    .SYNOPSIS
        Writes NetbiosOptions (1 = enabled, 2 = disabled) to every NetBT interface that
        declares the value and verifies each write was retained.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet(1, 2)]
        [int]$Option,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InterfacesRoot
    )

    $modeText = if ($Option -eq 1) { 'enabled' } else { 'disabled' }
    foreach ($interface in @(Get-ChildItem -LiteralPath $InterfacesRoot -ErrorAction Stop |
                Where-Object { $_.GetValueNames() -contains 'NetbiosOptions' })) {
        Set-ItemProperty -LiteralPath $interface.PSPath -Name 'NetbiosOptions' `
            -Value $Option -Type DWord -Force -ErrorAction Stop
        $key = Get-Item -LiteralPath $interface.PSPath -ErrorAction Stop
        try {
            if ($key.GetValueKind('NetbiosOptions') -ne
                [Microsoft.Win32.RegistryValueKind]::DWord -or
                [int]$key.GetValue('NetbiosOptions') -ne $Option) {
                throw "NetBIOS interface '$($interface.PSChildName)' did not retain $modeText mode."
            }
        }
        finally {
            $key.Close()
        }
    }
}

function Enable-VantaFileSharing {
    <#
    .SYNOPSIS
        Enables File Sharing: adapter bindings, NetBIOS, the NetBT driver and the
        Network Discovery machine state. Interactively (without -Silent) it also offers
        to switch active network profiles to Private with the sharing firewall groups,
        and to restore the 'Give access to' context menu.
    #>
    param(
        [switch]$Silent,

        # Toggle state store; the default is the toggle engine's own store.
        [ValidateNotNullOrEmpty()]
        [string]$StateRoot,

        # Tests can supply isolated registry roots.
        [ValidateNotNullOrEmpty()]
        [string]$NetBtInterfacesRoot = $script:VantaFileSharingNetBtInterfacesRoot,

        [ValidateNotNullOrEmpty()]
        [string]$ServicesRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    )

    if (-not $Silent) {
        Write-VantaStep -Text 'Enabling file sharing, NetBIOS and network discovery...'
    }
    Set-VantaFileSharingAdapterBinding -Enabled $true
    Set-VantaFileSharingNetBiosOption -Option 1 -InterfacesRoot $NetBtInterfacesRoot
    # Start value 1 is System: NetBT is a kernel driver that loads during kernel initialisation.
    Set-VantaServiceStartup -Name 'NetBT' -StartupType 1 -ServicesRoot $ServicesRoot

    # Network Discovery owns the rest of the service dependency chain, including SMB.
    $discoveryParameters = @{ Name = 'NetworkDiscovery'; State = 'Enable' }
    if ($PSBoundParameters.ContainsKey('StateRoot')) {
        $discoveryParameters['StateRoot'] = $StateRoot
    }
    Invoke-VantaToggleMachineState @discoveryParameters
    Write-VantaLog -Message 'Enabled File Sharing adapter bindings, NetBIOS, NetBT and Network Discovery.'

    if ($Silent) {
        return
    }

    if (Read-VantaYesNo -Question 'Switch your active networks to the Private profile so other devices can see this PC?') {
        foreach ($networkProfile in @(Get-NetConnectionProfile -ErrorAction Stop)) {
            if ([string]$networkProfile.NetworkCategory -cne 'Private') {
                Set-NetConnectionProfile -InputObject $networkProfile -NetworkCategory Private `
                    -ErrorAction Stop
            }
        }

        Enable-VantaPrivateSharingFirewallRule

        Set-VantaRegistryValue `
            -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\NcdAutoSetup\Private' `
            -Name 'AutoSetup' -Type DWord -Data 1
    }

    if (Read-VantaYesNo -Question "Restore the 'Give access to' context menu?") {
        foreach ($key in $script:VantaFileSharingContextMenuKeys) {
            Set-VantaRegistryValue -Path $key -Name '' -Type String `
                -Data $script:VantaFileSharingContextMenuClsid
        }
    }
}

function Disable-VantaFileSharing {
    <#
    .SYNOPSIS
        Disables File Sharing: adapter bindings, NetBIOS and the NetBT driver, then
        forces every network profile to Public, disables the Private sharing firewall
        groups and removes the 'Give access to' context menu.
    #>
    param(
        [switch]$Silent,

        # Tests can supply isolated registry roots.
        [ValidateNotNullOrEmpty()]
        [string]$NetBtInterfacesRoot = $script:VantaFileSharingNetBtInterfacesRoot,

        [ValidateNotNullOrEmpty()]
        [string]$ServicesRoot = 'HKLM:\SYSTEM\CurrentControlSet\Services'
    )

    if (-not $Silent) {
        Write-VantaStep -Text 'Disabling file sharing, NetBIOS and the sharing firewall rules...'
    }
    Set-VantaFileSharingAdapterBinding -Enabled $false
    Set-VantaFileSharingNetBiosOption -Option 2 -InterfacesRoot $NetBtInterfacesRoot
    # Start value 4 is Disabled.
    Set-VantaServiceStartup -Name 'NetBT' -StartupType 4 -ServicesRoot $ServicesRoot

    foreach ($networkProfile in @(Get-NetConnectionProfile -ErrorAction Stop)) {
        if ([string]$networkProfile.NetworkCategory -cne 'Public') {
            Set-NetConnectionProfile -InputObject $networkProfile -NetworkCategory Public `
                -ErrorAction Stop
        }
    }
    if (@(Get-NetConnectionProfile -ErrorAction Stop | Where-Object {
                [string]$_.NetworkCategory -cne 'Public'
            }).Count -ne 0) {
        throw 'File Sharing disable left a network profile outside the Public category.'
    }

    $rules = @(Get-VantaFileSharingFirewallRule)
    if ($rules.Count -ne 0) {
        Disable-NetFirewallRule -InputObject $rules -ErrorAction Stop | Out-Null
    }
    foreach ($rule in @(Get-VantaFileSharingFirewallRule)) {
        if ([string]$rule.Enabled -notin @('False', '0')) {
            throw "Firewall rule '$($rule.Name)' did not retain its disabled state."
        }
    }

    foreach ($key in $script:VantaFileSharingMachineContextMenuKeys) {
        Remove-VantaRegistryKey -Path $key
        if (Test-Path -LiteralPath $key -ErrorAction Stop) {
            throw "File Sharing disable left the context-menu key '$key'."
        }
    }
    Write-VantaLog -Message 'Disabled File Sharing adapter bindings, NetBIOS, NetBT, sharing firewall rules and the Sharing context menu.'
}
