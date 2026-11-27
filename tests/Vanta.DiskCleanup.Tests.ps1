BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:CleanupPath = Join-Path $script:VantaTestScriptsRoot 'Install\Tasks\Invoke-DiskCleanup.ps1'

    # Load the private cleanup functions without reaching either cleanup path.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        . $script:CleanupPath -Scope CurrentUser -ExpectedUserSid 'not-a-sid'
    }
    catch {
        if ($_.Exception.Message -notlike '*is invalid*') {
            throw
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

Describe 'Vanta disk cleanup scope' {
    It 'rejects a user SID on the machine cleanup path before doing work' {
        { & $script:CleanupPath -Scope Machine -ExpectedUserSid 'S-1-5-18' } |
            Should -Throw '*must not accept a user SID*'
    }

    It 'removes TEMP entries literally, including an AME folder that older releases left' {
        $temp = Join-Path $TestDrive 'Temp'
        # AME Wizard, which installed older Vanta releases, worked from TEMP\AME.
        $ame = Join-Path $temp 'AME'
        $nested = Join-Path $temp 'ordinary\nested'
        [void][IO.Directory]::CreateDirectory($ame)
        [void][IO.Directory]::CreateDirectory($nested)
        [IO.File]::WriteAllText((Join-Path $ame 'leftover.txt'), 'leftover')
        $readOnlyFile = Join-Path $nested 'remove.txt'
        [IO.File]::WriteAllText($readOnlyFile, 'remove')
        [IO.File]::SetAttributes($readOnlyFile, [IO.FileAttributes]::ReadOnly)

        Invoke-VantaTempCleanup -Path $temp

        [IO.Directory]::Exists($ame) | Should -BeFalse
        [IO.Directory]::Exists((Join-Path $temp 'ordinary')) | Should -BeFalse
        [IO.Directory]::Exists($temp) | Should -BeTrue
    }

    It 'deletes a directory junction without traversing or deleting its target' {
        $temp = Join-Path $TestDrive 'TempWithLink'
        $outside = Join-Path $TestDrive 'OutsideTarget'
        $link = Join-Path $temp 'linked'
        [void][IO.Directory]::CreateDirectory($temp)
        [void][IO.Directory]::CreateDirectory($outside)
        $sentinel = Join-Path $outside 'sentinel.txt'
        [IO.File]::WriteAllText($sentinel, 'keep')

        try {
            New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because "Directory junctions are unavailable: $($_.Exception.Message)"
            return
        }

        Invoke-VantaTempCleanup -Path $temp

        [IO.Directory]::Exists($link) | Should -BeFalse
        [IO.File]::Exists($sentinel) | Should -BeTrue
    }

    It 'ignores the current Windows root and detects a different Windows installation' {
        $script:SystemRootUnderTest = Join-Path $TestDrive 'SystemVolume'
        $script:OtherRootUnderTest = Join-Path $TestDrive 'OtherVolume'
        [void][IO.Directory]::CreateDirectory(
            (Join-Path $script:SystemRootUnderTest 'Windows'))
        [void][IO.Directory]::CreateDirectory(
            (Join-Path $script:OtherRootUnderTest 'Windows'))

        Mock Get-PSDrive {
            @([pscustomobject]@{ Root = $script:SystemRootUnderTest })
        }
        Test-VantaOtherWindowsInstall -SystemRoot $script:SystemRootUnderTest |
            Should -BeFalse

        Mock Get-PSDrive {
            @(
                [pscustomobject]@{ Root = $script:SystemRootUnderTest }
                [pscustomobject]@{ Root = $script:OtherRootUnderTest }
            )
        }
        Test-VantaOtherWindowsInstall -SystemRoot $script:SystemRootUnderTest |
            Should -BeTrue
    }

    It 'returns before every machine mutation when another Windows installation exists' {
        Mock Test-VantaOtherWindowsInstall { $true }
        Mock Invoke-VantaDiskCleanup {}
        Mock Invoke-VantaTempCleanup {}
        Mock Invoke-VantaSystemShadowCopyCleanup {}

        Invoke-VantaMachineCleanup -SystemRoot $TestDrive -WindowsRoot $TestDrive `
            -CleanMgrPath (Join-Path $TestDrive 'missing-cleanmgr.exe') `
            -VssAdminPath (Join-Path $TestDrive 'missing-vssadmin.exe')

        Should -Invoke Test-VantaOtherWindowsInstall -Times 1 -Exactly
        Should -Invoke Invoke-VantaDiskCleanup -Times 0 -Exactly
        Should -Invoke Invoke-VantaTempCleanup -Times 0 -Exactly
        Should -Invoke Invoke-VantaSystemShadowCopyCleanup -Times 0 -Exactly
    }
}
