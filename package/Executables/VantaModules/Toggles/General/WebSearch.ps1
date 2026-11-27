# Companion for the WebSearch toggle: turns web search and search highlights on or off, and
# installs the Bing search provider for Enable. The machine functions run as Administrator
# when you run a launcher, when the install applies Disable and when an update replays the
# recorded state. Enable-VantaWebSearchUser runs in your own unelevated process after Enable,
# and is replayed for each new account at first sign-in.

function Disable-VantaWebSearchMachine {
    param($Toggle)

    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation hide -Page search-permissions -NoProcessCleanup

    Import-VantaModule -Name Vanta.Appx
    Invoke-VantaAppxRemovalPlan -Definition @(
        [pscustomobject]@{
            Name         = 'Microsoft.BingSearch*'
            Option       = $null
            IgnoreErrors = $false
        }
    )
}

function Enable-VantaWebSearchMachine {
    param($Toggle)

    $locationKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    $useLocation = $null
    if (-not $Toggle.Silent) {
        $useLocation = Read-VantaYesNo -Question 'Let web search use your location for local results?'
    }
    if ($useLocation -eq $true) {
        Remove-VantaRegistryValue -Path $locationKey -Name 'AllowSearchToUseLocation'
    }
    elseif ($useLocation -eq $false) {
        Set-VantaRegistryValue -Path $locationKey `
            -Name 'AllowSearchToUseLocation' -Type DWord -Data 0
    }

    # Stopped search indexing shows a graphical bug in web search.
    $wsearch = Get-Service -Name wsearch -ErrorAction Stop
    if ($wsearch.Status -eq 'Stopped') {
        $enableIndexing = $false
        if (-not $Toggle.Silent) {
            Write-VantaWarning -Text 'Search indexing is stopped, which causes a display bug in web search.'
            $enableIndexing = Read-VantaYesNo -Question 'Turn on full search indexing to avoid it?'
        }
        if ($enableIndexing) {
            Write-VantaStep -Text 'Enabling full search indexing...'
            Import-VantaModule -Name Vanta.Search
            Set-VantaIndexingMachineState -State Full -PreservePowerModes
            # Full indexing was explicitly requested and successfully applied. Keep
            # its independent record consistent so upgrade replay preserves it.
            Set-VantaToggleState -Name Indexing -State 2 -StateRoot $Toggle.StateRoot
        }
    }

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Enabling web search and search highlights...'
    }
    Import-VantaModule -Name Vanta.Shell
    Set-VantaSettingsPageVisibility -Operation unhide -Page search-permissions -NoProcessCleanup
}

function Enable-VantaWebSearchUser {
    param($Toggle)

    if (-not $Toggle.Silent) {
        Write-VantaStep -Text 'Installing the Bing search provider from the Microsoft Store...'
    }
    Import-VantaModule -Name Vanta.Download
    $wingetPath = Get-VantaTrustedWingetPath
    Assert-VantaTrustedWingetSource -WingetPath $wingetPath -Name msstore
    [void](Invoke-VantaToggleNativeCommand `
            -FilePath $wingetPath `
            -ArgumentList ([string[]]@(
                    'install'
                    '--exact'
                    '--id'
                    '9NZBF4GT040C'
                    '--source'
                    'msstore'
                    '--uninstall-previous'
                    '--silent'
                    '--accept-source-agreements'
                    '--accept-package-agreements'
                    '--disable-interactivity'
                )) `
            -AllowedExitCodes ([int[]]@(0)))
}
