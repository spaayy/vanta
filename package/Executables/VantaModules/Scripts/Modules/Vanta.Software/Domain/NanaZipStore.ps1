# Use the inbox Store API used by WinGet's MSStore.cpp. Unlike the WinGet
# PowerShell module, this works in the installer's SYSTEM/Windows PowerShell host.

$script:VantaNanaZipStoreProductId = '9N8G7TSCL18R'

function New-VantaNanaZipStoreManager {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType=WindowsRuntime]
    $null = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallOptions, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType=WindowsRuntime]
    $null = [Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallItem, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType=WindowsRuntime]
    $null = [Windows.ApplicationModel.Store.Preview.InstallControl.GetEntitlementResult, Windows.ApplicationModel.Store.Preview.InstallControl, ContentType=WindowsRuntime]
    return New-Object Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallManager
}

function Wait-VantaStoreResult {
    param($Operation, [type]$ResultType, [int]$TimeoutSeconds = 120)
    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and
        $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1
    } | Select-Object -First 1
    $task = $method.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    if (-not $task.Wait($TimeoutSeconds * 1000)) {
        # Killing a client does not stop Store deployment. The pending marker
        # remains, preventing another installer from racing an unknown outcome.
        throw 'Microsoft Store did not respond in time. Restart Windows before retrying NanaZip installation.'
    }
    return $task.Result
}

function Get-VantaNanaZipStoreJournal {
    $path = 'HKLM:\SOFTWARE\Vanta\NanaZipStore'
    $boot = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToUniversalTime().ToString('o')
    $pending = $null
    if (Test-Path -LiteralPath $path -ErrorAction Stop) {
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        try { $pending = $key.GetValue('PendingBoot') } finally { $key.Close() }
    }
    return [pscustomobject]@{ Path = $path; Boot = $boot; Pending = ($pending -ceq $boot) }
}

function Set-VantaNanaZipStorePending {
    param($Journal, [bool]$Pending)
    if ($Pending) {
        New-Item -Path $Journal.Path -Force -ErrorAction Stop | Out-Null
        Set-ItemProperty -LiteralPath $Journal.Path -Name PendingBoot -Value $Journal.Boot -Type String -ErrorAction Stop
    }
    elseif (Test-Path -LiteralPath $Journal.Path -ErrorAction Stop) {
        Remove-ItemProperty -LiteralPath $Journal.Path -Name PendingBoot -ErrorAction Stop
    }
}

function Request-VantaNanaZipStoreInstall {
    param($Manager)
    $options = New-Object Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallOptions
    $options.InstallForAllUsers = $true
    $options.AllowForcedAppRestart = $false
    $options.InstallInProgressToastNotificationMode = 'NoToast'
    $options.CompletedInstallToastNotificationMode = 'NoToast'
    return @(Wait-VantaStoreResult -Operation ($Manager.StartProductInstallAsync($script:VantaNanaZipStoreProductId, '', 'Vanta', '', $options)) `
        -ResultType ([System.Collections.Generic.IReadOnlyList[Windows.ApplicationModel.Store.Preview.InstallControl.AppInstallItem]]))
}

function Get-VantaNanaZipStoreEntitlement {
    param($Manager)
    $entitlement = Wait-VantaStoreResult -Operation ($Manager.GetFreeDeviceEntitlementAsync($script:VantaNanaZipStoreProductId, '', '')) `
        -ResultType ([Windows.ApplicationModel.Store.Preview.InstallControl.GetEntitlementResult])
    if ([string]$entitlement.Status -ne 'Succeeded') { throw "Store entitlement: $($entitlement.Status)" }
}

function Get-VantaNanaZipStoreItems {
    param($Manager)
    return @($Manager.AppInstallItems | Where-Object { $_.ProductId -ceq $script:VantaNanaZipStoreProductId })
}

function Wait-VantaNanaZipStoreItems {
    param($Manager, [object[]]$Items, [int]$TimeoutSeconds = 600)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $restarted = @{}
    $previous = ''
    do {
        $active = 0
        $failed = $false
        $descriptions = foreach ($item in $Items) {
            $status = $item.GetCurrentStatus()
            $state = [string]$status.InstallState
            $code = if ($null -ne $status.ErrorCode) { '0x{0:X8}' -f $status.ErrorCode.HResult } else { '0x00000000' }
            "$($item.ProductId): $state ($([int]$status.PercentComplete)%, $code)"
            if ($state -in @('Error', 'Canceled')) { $failed = $true; continue }
            if ($state -eq 'Completed') { continue }
            $active++
            if ($state -in @('ReadyToDownload', 'Paused') -and -not $restarted.ContainsKey($item.ProductId)) {
                $Manager.Restart($item.ProductId)
                $restarted[$item.ProductId] = $true
            }
        }
        $description = $descriptions -join '; '
        if ($description -cne $previous) {
            Write-VantaLog -Message "NanaZip Microsoft Store: $description"
            $previous = $description
        }
        if ($active -eq 0) { return (-not $failed) }
        if ([DateTime]::UtcNow -ge $deadline) {
            throw [TimeoutException]::new('NanaZip is still queued or installing in Microsoft Store.')
        }
        Start-Sleep -Seconds 2
    } while ($true)
}

function Stop-VantaNanaZipStoreInstall {
    param($Manager, [object[]]$Items, [int]$Attempts = 30)
    Write-VantaLog -Level Warning -Message 'NanaZip Store timed out. Canceling its request before considering verified downloads.'
    $Manager.Cancel($script:VantaNanaZipStoreProductId)
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        # Cancellation is asynchronous. Retain the operation handles so an empty
        # queue alone cannot hide an in-flight deployment or dependency.
        $active = @($Items | Where-Object { [string]$_.GetCurrentStatus().InstallState -notin @('Completed','Canceled','Error') })
        $queue = @(Get-VantaNanaZipStoreItems -Manager $Manager)
        if ($active.Count -eq 0 -and $queue.Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw 'Microsoft Store has not confirmed NanaZip cancellation. No fallback installer was started. Finish or cancel NanaZip in Microsoft Store, then retry with your original Vanta choices.'
}

function Install-VantaNanaZipFromStore {
    param($DismCommands)
    # Returns $false when Store activation or entitlement fails, so the caller
    # provisions NanaZip from the pinned, verified downloads instead.
    $journal = Get-VantaNanaZipStoreJournal
    try {
        $manager = New-VantaNanaZipStoreManager
        if (-not $manager.CanInstallForAllUsers) { throw 'Store cannot install for all users in this context.' }
        $items = @(Get-VantaNanaZipStoreItems -Manager $manager)
    }
    catch {
        if ($journal.Pending) { throw 'An earlier NanaZip Store request has an unknown outcome. Restart Windows before retrying.' }
        Write-VantaLog -Level Warning -Message "NanaZip Store is unavailable; using verified downloads. $($_.Exception.Message)"
        return $false
    }
    if ($journal.Pending -and $items.Count -eq 0) {
        throw 'An earlier NanaZip Store request has an unknown outcome. Restart Windows before retrying.'
    }
    if ($items.Count -gt 0) { Set-VantaNanaZipStorePending -Journal $journal -Pending $true }
    if ($items.Count -eq 0) {
        try {
            Get-VantaNanaZipStoreEntitlement -Manager $manager
        }
        catch {
            Write-VantaLog -Level Warning -Message "NanaZip Store entitlement is unavailable; using verified downloads. $($_.Exception.Message)"
            return $false
        }
        Write-VantaLog -Message "Installing NanaZip from Microsoft Store ($script:VantaNanaZipStoreProductId) for all users."
        Set-VantaNanaZipStorePending -Journal $journal -Pending $true
        # Exceptions here are intentionally not converted into a download retry:
        # even a failed RPC may have queued deployment in the Store service.
        $items = @(Request-VantaNanaZipStoreInstall -Manager $manager)
        if ($items.Count -eq 0) { throw 'Microsoft Store returned no NanaZip install operation. Restart Windows before retrying.' }
    }
    $canceled = $false
    try {
        $completed = Wait-VantaNanaZipStoreItems -Manager $manager -Items $items
        # Recheck the service queue before permitting a different installer.
        $queue = @(Get-VantaNanaZipStoreItems -Manager $manager)
        if ($queue.Count -gt 0) {
            $items = @($items) + @($queue)
            $completed = (Wait-VantaNanaZipStoreItems -Manager $manager -Items $queue) -and $completed
        }
    } catch [TimeoutException] {
        Stop-VantaNanaZipStoreInstall -Manager $manager -Items $items
        $canceled = $true
        $completed = $false
    }
    # Provisioning can appear shortly after Store reports Completed.
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $packages = @(& $DismCommands.GetProvisionedPackage -Online -ErrorAction Stop)
        if (Test-VantaNanaZipProvisioned -Package $packages) {
            Set-VantaNanaZipStorePending -Journal $journal -Pending $false
            Write-VantaLog -Message 'Verified NanaZip Microsoft Store provisioning for all users.'
            return $true
        }
        if (-not $completed) { break }
        Start-Sleep -Seconds 2
    }
    if ($completed) {
        throw 'Microsoft Store completed NanaZip installation but machine provisioning could not be verified. Restart Windows before retrying.'
    }
    if ($canceled) {
        Set-VantaNanaZipStorePending -Journal $journal -Pending $false
        Write-VantaLog -Level Warning -Message 'Confirmed NanaZip Store cancellation; using verified downloads.'
        return $false
    }
    # Failed or cancelled jobs are terminal. Clear only NanaZip's queue record and
    # confirm it is gone before starting the pinned GitHub/SourceForge fallback.
    $manager.Cancel($script:VantaNanaZipStoreProductId)
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        if (@(Get-VantaNanaZipStoreItems -Manager $manager).Count -eq 0) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($attempt -eq 25) {
        throw 'Microsoft Store has not cleared the failed NanaZip operation. Restart Windows before retrying.'
    }
    Set-VantaNanaZipStorePending -Journal $journal -Pending $false
    Write-VantaLog -Level Warning -Message 'NanaZip Store installation failed and its queue is clear; using verified downloads.'
    return $false
}
