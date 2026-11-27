# Vanta.Hardware domain: Plug and Play device state.

function Import-VantaPnpDeviceModule {
    $pnpModulePath = Join-Path -Path ([Environment]::GetFolderPath('System')) `
        -ChildPath 'WindowsPowerShell\v1.0\Modules\PnpDevice\PnpDevice.psd1'
    if (-not [IO.File]::Exists($pnpModulePath)) {
        throw "The inbox PnpDevice module is missing at '$pnpModulePath'."
    }
    Microsoft.PowerShell.Core\Import-Module -Name $pnpModulePath -Force -ErrorAction Stop
}

function Get-VantaPresentPnpDevice {
    return @(PnpDevice\Get-PnpDevice -PresentOnly -ErrorAction Stop)
}

function Get-VantaPnpDeviceParentId {
    <#
    .SYNOPSIS
        Returns the instance ID of an enumerated device's parent, or $null for the root.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device
    )

    # Asked of the enumerated instance itself. Get-PnpDeviceProperty runs a new query
    # for every call, and given several instance IDs it can drop or repeat results.
    $result = CimCmdlets\Invoke-CimMethod -InputObject $Device -MethodName 'GetDeviceProperties' `
        -Arguments @{ devicePropertyKeys = [string[]]@('DEVPKEY_Device_Parent') } -ErrorAction Stop
    if ([int]$result.ReturnValue -ne 0) {
        throw "Reading the parent of device '$($Device.InstanceId)' returned $($result.ReturnValue)."
    }
    foreach ($property in @($result.deviceProperties)) {
        if ($null -eq $property) {
            continue
        }
        # The root device's property has no Data at all.
        $data = $property.CimInstanceProperties['Data']
        if ($null -ne $data -and -not [string]::IsNullOrWhiteSpace([string]$data.Value)) {
            return [string]$data.Value
        }
    }
    return $null
}

function Test-VantaPnpDeviceDisabled {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device
    )

    # Problem code 22 (CM_PROB_DISABLED): the device carries its own disable flag.
    $code = $Device.PSObject.Properties['ConfigManagerErrorCode']
    return $null -ne $code -and $null -ne $code.Value -and [int]$code.Value -eq 22
}

function Select-VantaMatchedPnpDevice {
    <#
    .SYNOPSIS
        Returns the devices whose friendly name matches one of the patterns, refusing a
        matched device with an invalid instance ID.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Device,

        [Parameter(Mandatory = $true)]
        [string[]]$NamePattern
    )

    $matchedDevices = @($Device | Where-Object {
            $friendlyName = [string]$_.FriendlyName
            if ([string]::IsNullOrWhiteSpace($friendlyName)) {
                return $false
            }
            foreach ($candidate in $NamePattern) {
                if ($friendlyName -like $candidate) {
                    return $true
                }
            }
            return $false
        })

    foreach ($device in $matchedDevices) {
        $instanceId = [string]$device.InstanceId
        if ([string]::IsNullOrWhiteSpace($instanceId) -or
            $instanceId.Length -gt 4096 -or
            $instanceId.IndexOf([char]0) -ge 0) {
            throw "Matched device '$($device.FriendlyName)' has an invalid instance ID."
        }
    }
    return $matchedDevices
}

function Get-VantaPnpDeviceWithoutMatchedAncestor {
    <#
    .SYNOPSIS
        Returns the given devices that have none of the others above them in the device
        tree, at any depth. PresentDevice is the enumeration they came from, which holds
        every ancestor of a present device.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Device,

        [Parameter(Mandatory = $true)]
        [object[]]$PresentDevice
    )

    $presentById = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($present in $PresentDevice) {
        $presentById[[string]$present.InstanceId] = $present
    }
    $matchedIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $Device) {
        [void]$matchedIds.Add([string]$candidate.InstanceId)
    }

    $parentIds = @{}
    $uncovered = New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($candidate in $Device) {
            $ancestorId = [string]$candidate.InstanceId
            $covered = $false
            # The bound only stops a malformed answer from looping.
            for ($depth = 0; $depth -lt 64 -and -not $covered; $depth++) {
                if (-not $parentIds.ContainsKey($ancestorId)) {
                    $parentIds[$ancestorId] = if ($presentById.ContainsKey($ancestorId)) {
                        [string](Get-VantaPnpDeviceParentId -Device $presentById[$ancestorId])
                    }
                    else {
                        ''
                    }
                }
                $ancestorId = $parentIds[$ancestorId]
                if ($ancestorId.Length -eq 0) {
                    break
                }
                $covered = $matchedIds.Contains($ancestorId)
            }
            if (-not $covered) {
                $uncovered.Add($candidate)
            }
        }
    }
    catch {
        # Each device is then changed on its own, which Enable can still undo.
        Write-VantaLog -Level Warning -Message (
            "Couldn't read the device tree, so each matched device is changed on its own: $($_.Exception.Message)")
        return $Device
    }
    return $uncovered.ToArray()
}

function Set-VantaPnpDeviceState {
    <#
    .SYNOPSIS
        Enables or disables one device instance. A provider failure is a terminating
        error; success produces no output.
    .NOTES
        Enable-/Disable-PnpDevice report a failed Win32_PnPEntity method through the
        error stream. -PassThru only echoes the device object and carries no result
        code, so success is the absence of an error.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Enable', 'Disable')]
        [string]$State
    )

    if ($State -ceq 'Enable') {
        PnpDevice\Enable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
    }
    else {
        PnpDevice\Disable-PnpDevice -InstanceId $InstanceId -Confirm:$false -ErrorAction Stop | Out-Null
    }
}

function Set-VantaMatchedPnpDeviceState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Device,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Enable', 'Disable')]
        [string]$State
    )

    $instanceId = [string]$Device.InstanceId
    try {
        Set-VantaPnpDeviceState -InstanceId $instanceId -State $State | Out-Null
    }
    catch {
        $action = if ($State -ceq 'Enable') { 'Enabling' } else { 'Disabling' }
        throw ("{0} device '{1}' ({2}) failed: {3}" -f `
                $action,
                [string]$Device.FriendlyName,
                $instanceId,
                $_.Exception.Message)
    }
}

function Enable-VantaReenumeratedPnpDevice {
    <#
    .SYNOPSIS
        Enables the matched devices that come back disabled once their parent has
        started, and returns the devices it enabled.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$NamePattern,

        # The matched devices seen before enabling.
        [Parameter(Mandatory = $true)]
        [object[]]$InitialDevice
    )

    # A started device enumerates its children afterwards, and a child disabled in its
    # own right, by Device Manager or an earlier Disable, comes back still disabled.
    # Poll until two passes in a row see the same devices, none of them disabled, and
    # not just the devices seen before enabling: a slow parent may not have enumerated
    # its children yet.
    $initialIds = @($InitialDevice | ForEach-Object { ([string]$_.InstanceId).ToUpperInvariant() } | Sort-Object) -join '|'
    $previousIds = $null
    for ($pass = 1; $pass -le 5; $pass++) {
        Start-Sleep -Seconds 2
        $present = @(Select-VantaMatchedPnpDevice -Device @(Get-VantaPresentPnpDevice) -NamePattern $NamePattern)
        $disabled = @($present | Where-Object { Test-VantaPnpDeviceDisabled -Device $_ })
        foreach ($device in $disabled) {
            Set-VantaMatchedPnpDeviceState -Device $device -State Enable
            $device
        }

        $ids = @($present | ForEach-Object { ([string]$_.InstanceId).ToUpperInvariant() } | Sort-Object) -join '|'
        if ($disabled.Count -eq 0 -and $ids -ceq $previousIds -and $ids -cne $initialIds) {
            return
        }
        $previousIds = $ids
    }

    if ($previousIds -ceq $initialIds) {
        Write-VantaLog -Message ('No other matched devices appeared within 10 seconds of enabling. ' +
            "A matched child that appears later isn't checked for its own disable flag.")
    }
    $stillDisabled = @(Select-VantaMatchedPnpDevice -Device @(Get-VantaPresentPnpDevice) -NamePattern $NamePattern |
            Where-Object { Test-VantaPnpDeviceDisabled -Device $_ })
    if ($stillDisabled.Count -gt 0) {
        Write-VantaLog -Level Warning -Message ("Matched device(s) still disabled after enabling: {0}." -f
            (@($stillDisabled | ForEach-Object { "$($_.FriendlyName) ($($_.InstanceId))" }) -join ', '))
    }
}

function Set-VantaDeviceState {
    <#
    .SYNOPSIS
        Enables or disables every present Plug and Play device whose friendly name
        matches one of the given wildcard patterns. No match is an error unless
        -AllowNoMatch is given; a provider failure is always an error. Disable leaves a
        matched device to a matched ancestor, and Enable also enables matched devices
        that reappear disabled once their parent starts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Enable', 'Disable')]
        [string]$State,

        # Friendly-name wildcard patterns, for example '*Bluetooth*'.
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Devices,

        [switch]$AllowNoMatch,

        [switch]$Silent
    )

    foreach ($pattern in $Devices) {
        if ([string]::IsNullOrWhiteSpace($pattern) -or
            $pattern.Length -gt 256 -or
            $pattern.IndexOf([char]0) -ge 0) {
            throw 'Every device-friendly-name pattern must be nonempty and at most 256 characters.'
        }
    }

    $verb = if ($State -ceq 'Enable') { 'Enabl' } else { 'Disabl' }
    Import-VantaPnpDeviceModule

    # Enumerate with Stop semantics, then apply the caller's friendly-name patterns
    # locally. Get-PnpDevice -FriendlyName reports no-match and provider failures through
    # the same error stream; treating an empty, successful enumeration separately keeps an
    # explicit AllowNoMatch from concealing provider/RPC failures.
    $allDevices = @(Get-VantaPresentPnpDevice)
    $foundDevices = @(Select-VantaMatchedPnpDevice -Device $allDevices -NamePattern $Devices)
    if ($foundDevices.Count -eq 0) {
        if ($AllowNoMatch) {
            Write-VantaLog -Message "No present devices matched the requested friendly-name pattern(s): $($Devices -join ', ')."
            if (-not $Silent) {
                Write-VantaNote -Text 'No matching devices are present on this PC, so there was nothing to change.'
            }
            return
        }
        throw "No present devices matched: $($Devices -join ', ')."
    }

    $targets = $foundDevices
    if ($State -ceq 'Disable' -and $foundDevices.Count -gt 1) {
        # Disabling a device removes its children with it. A matched child disabled in
        # its own right would keep that flag and come back disabled with its parent.
        $targets = @(Get-VantaPnpDeviceWithoutMatchedAncestor -Device $foundDevices -PresentDevice $allDevices)
        if ($targets.Count -lt $foundDevices.Count) {
            $targetIds = @($targets | ForEach-Object { [string]$_.InstanceId })
            $children = @($foundDevices | Where-Object { $targetIds -notcontains [string]$_.InstanceId } |
                    ForEach-Object { [string]$_.FriendlyName })
            Write-VantaLog -Message ("Left {0} matched device(s) to a matched parent: {1}." -f
                $children.Count, ($children -join ', '))
        }
    }

    $changed = New-Object 'System.Collections.Generic.List[object]'
    $changedIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($device in $targets) {
        Set-VantaMatchedPnpDeviceState -Device $device -State $State
        if ($changedIds.Add([string]$device.InstanceId)) {
            $changed.Add($device)
        }
    }

    if ($State -ceq 'Enable' -and
        @($targets | Where-Object { Test-VantaPnpDeviceDisabled -Device $_ }).Count -gt 0) {
        foreach ($device in @(Enable-VantaReenumeratedPnpDevice -NamePattern $Devices -InitialDevice $foundDevices)) {
            if ($changedIds.Add([string]$device.InstanceId)) {
                $changed.Add($device)
            }
        }
    }

    $friendlyNames = @($changed | ForEach-Object { [string]$_.FriendlyName })
    Write-VantaLog -Message ("{0}ed {1} matched device(s): {2}." -f $verb, $friendlyNames.Count, ($friendlyNames -join ', '))
    if (-not $Silent) {
        Write-VantaSuccess -Text ("{0}ed {1} device(s):" -f $verb, $friendlyNames.Count)
        Write-VantaNote -Text ([string[]]@($friendlyNames | ForEach-Object { "  - $_" }))
    }
}
