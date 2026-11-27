# Companion for the FixMSStoreIssues toggle: runs StoreFixer. Invoke-VantaStoreFixer runs in
# the silent TrustedInstaller broker when you run the launcher; nothing is recorded.

function Invoke-VantaStoreFixer {
    param($Toggle)

    $storeFixer = Join-Path -Path $Toggle.VantaModulesPath -ChildPath 'Tools\StoreFixer.exe'
    if (-not (Test-Path -LiteralPath $storeFixer -PathType Leaf)) {
        throw "Required StoreFixer executable is missing: '$storeFixer'."
    }

    # The TrustedInstaller broker always runs this silently.
    Invoke-VantaToggleNativeCommand -FilePath $storeFixer -ArgumentList ([string[]]@('silent', '-wait')) `
        -AllowedExitCodes ([int[]]@(0)) | Out-Null
}
