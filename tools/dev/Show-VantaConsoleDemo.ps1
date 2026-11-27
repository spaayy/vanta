<#
.SYNOPSIS
    Renders the Vanta console vocabulary and five representative launcher flows
    without touching the machine.
.DESCRIPTION
    Imports the Vanta.Core module, feeds scripted answers to its prompts and
    prints exactly what a user would see for: a simple declarative toggle, a
    multi-question flow, a failure, a manual Settings hand-over and a menu toggle
    given an invalid answer first. Nothing is applied,
    elevated, recorded or logged to the shared install log; the only side effect is
    console output. Run it under Windows PowerShell 5.1, the runtime Vanta uses on users' PCs:

        powershell -NoProfile -File tools\dev\Show-VantaConsoleDemo.ps1

.PARAMETER NoColor
    Shows the plain-text rendering a transcript or a monochrome console produces.
.NOTES
    Exit codes: 0 rendered, 1 the Vanta.Core module could not be loaded or a prompt
    failed.
#>
[CmdletBinding()]
param(
    [switch]$NoColor
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
$coreManifest = Join-Path -Path $repoRoot -ChildPath 'package\Executables\VantaModules\Scripts\Modules\Vanta.Core\Vanta.Core.psd1'
$core = Import-Module -Name $coreManifest -Force -PassThru

# Scripted answers replace the keyboard; the prompt text is still printed so the
# rendering matches a real window.
$script:DemoAnswers = New-Object 'System.Collections.Generic.Queue[string]'
& $core {
    Set-Item -Path 'function:Read-VantaConsoleLine' -Value {
        param([string]$Prompt)
        $answer = if ($script:DemoAnswerSource.Count -gt 0) { $script:DemoAnswerSource.Dequeue() } else { '' }
        Write-Host ($Prompt + $answer)
        return $answer
    }
}
& $core { param($Queue) $script:DemoAnswerSource = $Queue } $script:DemoAnswers

if ($NoColor) {
    & $core {
        Set-Item -Path 'function:Write-VantaUiText' -Value {
            param([string[]]$Text, [string]$Prefix = '', [string]$Color)
            [void]$Color
            foreach ($line in (Get-VantaUiLine -Text $Text -Prefix $Prefix)) { Write-Host $line }
        }
    }
}

function Show-DemoSection {
    param([string]$Caption)
    Write-Host ''
    Write-Host "==== $Caption ====" -ForegroundColor DarkGray
    Write-Host ''
}

function Add-DemoAnswer {
    param([string[]]$Answer)
    foreach ($item in $Answer) { $script:DemoAnswers.Enqueue($item) }
}

Show-DemoSection 'Vocabulary'
Write-VantaTitle -Text 'Vocabulary sample' -Explanation 'Every kind of line the launchers print.'
Write-VantaNote -Text 'A note gives context in plain words.'
Write-VantaStep -Text 'A step announces slow work. This can take a minute...'
Write-VantaWarning -Text "A warning names a concrete consequence.`nContinuation lines line up under the text."
Write-VantaSuccess -Text 'A success line states a verified fact.'
Write-VantaNextStep -Text 'A next step is advice after a completed change.'
Write-VantaRestartNotice -Kind Recommended
Write-VantaFailure -Text 'An error names the reason something did not happen.'

Show-DemoSection 'Simple toggle: Disable Background Apps (default)'
Reset-VantaRunOutcome
Add-DemoAnswer ''
Write-VantaTitle -Text 'Disable Background Apps (default)'
Write-VantaCompletion -Title 'Disable Background Apps (default)'
Wait-VantaExit

Show-DemoSection 'Multi-option flow: Enable File Sharing (standard user, administrator credentials)'
Reset-VantaRunOutcome
Add-DemoAnswer 'n', 'y', 'y', 'n', ''
Write-VantaTitle -Text 'Enable File Sharing'
Write-VantaStep -Text 'Asking for administrator permission...'
Write-Host '    (administrator window)'
Write-Host '    Vanta - Enable File Sharing'
Write-Host '    -----------------------------'
Write-Host '    Administrator step for the change started in the other window.'
Write-Host ''
Write-Host '    Enabling file sharing, NetBIOS and network discovery...'
Write-Host -NoNewline '    '
$null = Read-VantaYesNo -Question 'Switch your active networks to the Private profile so other devices can see this PC?'
Write-Host -NoNewline '    '
$null = Read-VantaYesNo -Question "Restore the 'Give access to' context menu?"
$null = Read-VantaYesNo -Question 'Add Network to the File Explorer navigation pane?'
Write-Host '    (administrator window records that separate choice)'
Write-VantaCompletion -Title 'Enable File Sharing'
Write-VantaRestartNotice -Kind Required
$null = Read-VantaYesNo -Question 'Restart Windows now?'
Wait-VantaExit

Show-DemoSection 'Failure: Enable Widgets with Edge missing and its installation declined'
Reset-VantaRunOutcome
Add-DemoAnswer 'n', '', ''
Write-VantaTitle -Text 'Enable Widgets'
Write-VantaStep -Text 'Asking for administrator permission...'
Write-Host '    (administrator window)'
Write-Host '    Vanta - Enable Widgets'
Write-Host '    ------------------------'
Write-Host '    Administrator step for the change started in the other window.'
Write-Host ''
Write-Host '    Widgets needs Microsoft Edge, which is not installed.'
Write-Host -NoNewline '    '
$null = Read-VantaYesNo -Question 'Install Microsoft Edge now?'
Write-VantaNotApplied -Title 'Enable Widgets' -Reason 'Microsoft Edge is not installed and its installation was declined.' `
    -DetailsPath 'C:\Windows\VantaOS\Logs\install\vanta-install.log'
Wait-VantaExit
Write-Host ''
Write-VantaNotApplied -Title 'Enable Widgets' `
    -Reason "The administrator step for 'Widgets' did not complete (exit code 1). Its window shows the reason." `
    -DetailsPath "$env:LOCALAPPDATA\Vanta\Logs\install\vanta-install.log"
Wait-VantaExit

Show-DemoSection 'Manual Settings action: Remove Python Store Prompt'
Reset-VantaRunOutcome
Add-DemoAnswer ''
Write-VantaTitle -Text 'Remove Python Store Prompt'
Write-VantaNote -Text @(
    'Windows cannot tell which package owns a python.exe alias, so Vanta opens the'
    'Settings page and leaves the choice to you. No Python files are deleted.'
)
Write-VantaBlankLine
Write-VantaStep -Text 'Opening Settings > Apps > Advanced app settings...'
Write-VantaManualStep -Text @(
    'select App execution aliases, then turn off python.exe and python3.exe'
    'under App Installer. Keep the aliases of any Python you installed yourself.'
)
Write-VantaNote -Text 'If Settings did not open that page, go to Apps > Advanced app settings.'
Write-VantaCompletion -Title 'Remove Python Store Prompt'
Wait-VantaExit

Show-DemoSection 'Menu toggle: Toggle Defender with an invalid answer first'
Reset-VantaRunOutcome
Add-DemoAnswer '5', '1', '', 'n', ''
Write-VantaTitle -Text 'Toggle Defender'
Write-VantaNote -Text 'Only disable Windows Defender after reading the Vanta documentation.'
Write-VantaBlankLine
$choice = Read-VantaChoice -Question 'What would you like to do?' `
    -Option @('Disable Windows Defender', 'Enable Windows Defender', 'Open the documentation') -CurrentIndex 2
Write-VantaBlankLine
Write-VantaWarning -Text @(
    'Disabling Windows Defender leaves this PC without real-time antivirus protection.'
    'Malware and unwanted software will no longer be blocked automatically.'
)
Wait-VantaContinue
Write-VantaStep -Text 'Disabling Windows Defender. This can take a few minutes...'
Write-VantaCompletion -Title 'Toggle Defender'
Write-VantaRestartNotice -Kind Required
$null = Read-VantaYesNo -Question 'Restart Windows now?'
Wait-VantaExit
[void]$choice
