# Vanta.Registry domain: registry key creation and removal.

function New-VantaRegistryKey {
    <#
    .SYNOPSIS
        Creates a registry key (and any missing parents). HKCU is either the proven
        current token's ambient hive or the explicitly bound fixed default-user hive.
        An existing key is not an error.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Invoke-VantaRegistryTargetOperation -Path $Path -Action {
        param($providerPath)

        $split = Split-VantaRegistryProviderPath -ProviderPath $providerPath
        if (-not $split.SubPath) {
            return
        }

        $key = $split.BaseKey.CreateSubKey($split.SubPath)
        if ($null -eq $key) {
            throw "Failed to create the registry key '$providerPath'."
        }

        $key.Close()
    }
}

function Remove-VantaRegistryKey {
    <#
    .SYNOPSIS
        Recursively deletes a registry key if it exists (a missing key is not an error),
        with the same token/default-user scope binding as
        New-VantaRegistryKey.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $pathInfo = ConvertTo-VantaRegistryPathInfo -Path $Path
    # A bare HKCU resolves to a whole user hive under HKU, which the root check
    # inside the action cannot see.
    if ($pathInfo.Root -eq 'HKEY_CURRENT_USER' -and [string]::IsNullOrEmpty($pathInfo.SubPath)) {
        throw "Refusing to delete the registry root '$Path'."
    }

    Invoke-VantaRegistryTargetOperation -Path $Path -Action {
        param($providerPath)

        $split = Split-VantaRegistryProviderPath -ProviderPath $providerPath
        if (-not $split.SubPath) {
            throw "Refusing to delete the registry root '$providerPath'."
        }

        # The second argument suppresses the missing-key exception.
        $split.BaseKey.DeleteSubKeyTree($split.SubPath, $false)
    }
}
