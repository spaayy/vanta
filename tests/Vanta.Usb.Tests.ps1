BeforeAll {
    . (Join-Path $PSScriptRoot 'VantaTestHost.ps1')
    $script:UsbScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'app\resources\iso\Write-Usb.ps1'
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($script:UsbScript,[ref]$null,[ref]$errors)
    if ($errors) { throw ($errors | Out-String) }
    foreach ($name in @('Fail','Read-VantaUsbRequest','Get-VantaUsbIdentity','Test-VantaUsbDisk','Assert-VantaUsbIdentity','Assert-VantaUsbPaths','Assert-VantaUsbContinue','Write-VantaUsbProgress','Copy-VantaUsbFile','Get-VantaUsbDeviceHash','Test-VantaUsbCopy','Get-VantaUsbParentPath','Assert-VantaUsbVolume','Get-VantaUsbVolumeId','Get-VantaUsbTargetRoot','Format-VantaUsb','Get-VantaUsbEjectTarget','Get-VantaUsbMediaInfo')) {
        $node = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        . ([scriptblock]::Create($node.Extent.Text))
    }
}

Describe 'USB media architecture validation before erasing' {
    BeforeEach {
        $script:MediaRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $MediaRoot 'sources'),(Join-Path $MediaRoot 'efi\boot') -Force | Out-Null
        foreach ($file in @('setup.exe','sources\boot.wim','sources\install.wim','efi\boot\bootx64.efi','efi\boot\bootaa64.efi')) { Set-Content -LiteralPath (Join-Path $MediaRoot $file) 'fixture' }
        $script:MediaImages = @([pscustomobject]@{ImageIndex=1;Architecture=9;Version='10.0.26200.8037';InstallationType='Client'})
        Mock Get-WindowsImage {
            param($Index)
            if ($Index) { $script:MediaImages | Where-Object ImageIndex -eq $Index } else { $script:MediaImages }
        }
        # The reason is what the app shows; the message only reaches the log.
        Mock Fail { throw "$Reason|$Message" }
    }
    It 'uses the matching UEFI loader for architecture <Architecture>' -ForEach @(
        @{Architecture=9; OtherLoader='bootaa64.efi'}, @{Architecture=12; OtherLoader='bootx64.efi'}
    ) {
        $script:MediaImages[0].Architecture = $Architecture
        Remove-Item -LiteralPath (Join-Path $MediaRoot ('efi\boot\'+$OtherLoader))
        (Get-VantaUsbMediaInfo $MediaRoot @(26200)).architecture | Should -Be $Architecture
    }
    It 'rejects ARM64 media containing only an x64 loader' {
        $script:MediaImages[0].Architecture = 12
        Remove-Item -LiteralPath (Join-Path $MediaRoot 'efi\boot\bootaa64.efi')
        { Get-VantaUsbMediaInfo $MediaRoot @(26200) } | Should -Throw 'iso-unsupported|*bootaa64.efi*'
    }
    It 'accepts 26H2 installation media for architecture <Architecture> when the package lists it' -ForEach @(@{Architecture=9},@{Architecture=12}) {
        $script:MediaImages[0].Architecture = $Architecture
        $script:MediaImages[0].Version = '10.0.26300.9457'
        (Get-VantaUsbMediaInfo $MediaRoot @(26200,26300)).architecture | Should -Be $Architecture
    }
    It 'rejects a build the package does not list' {
        $script:MediaImages[0].Version = '10.0.26300.9457'
        { Get-VantaUsbMediaInfo $MediaRoot @(26200) } | Should -Throw 'iso-unsupported|*'
    }
    It 'supports nothing when no builds are supplied' {
        { Get-VantaUsbMediaInfo $MediaRoot @() } | Should -Throw 'iso-unsupported|*'
        { Get-VantaUsbMediaInfo $MediaRoot } | Should -Throw 'iso-unsupported|*'
    }
    It 'rejects mixed architectures' {
        $script:MediaImages += [pscustomobject]@{ImageIndex=2;Architecture=12;Version='10.0.26200.8037';InstallationType='Client'}
        { Get-VantaUsbMediaInfo $MediaRoot @(26200) } | Should -Throw 'iso-unsupported|*Mixed x64 and ARM64*'
    }
    It 'rejects empty installation images' {
        $script:MediaImages = @()
        { Get-VantaUsbMediaInfo $MediaRoot @(26200) } | Should -Throw 'iso-unsupported|*no Windows installation images*'
    }
    It 'still rejects 32-bit and wrong-build images' -ForEach @(
        @{Architecture=0;Version='10.0.26200.8037'}, @{Architecture=12;Version='10.0.26100.8037'}
    ) {
        $script:MediaImages[0].Architecture = $Architecture
        $script:MediaImages[0].Version = $Version
        { Get-VantaUsbMediaInfo $MediaRoot @(26200,26300) } | Should -Throw 'iso-unsupported|*x64 or ARM64*'
    }
}

Describe 'USB worker request and module resolution' {
    It 'reads a request with non-ASCII paths and names exactly as the app writes it' {
        # Built from code points so this file's own encoding cannot hide a decoding fault.
        $source = "C:\Users\Jos$([char]0xE9)\Downloads\Windows.iso"
        $app = "C:\Users\$([char]0x674E)\Downloads\VantaManager.exe"
        $name = "Cl$([char]0xE9) $([char]0x424)"
        $path = Join-Path $TestDrive 'usb-request.json'
        $json = @{ source=$source; app=$app; drive=@{ name=$name } } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
        $request = Read-VantaUsbRequest $path
        $request.source | Should -BeExactly $source
        $request.app | Should -BeExactly $app
        $request.drive.name | Should -BeExactly $name
    }
    It 'writes the drive list as UTF-8 so non-ASCII names reach the app intact' {
        $job = Join-Path $TestDrive 'encoding'
        [void][IO.Directory]::CreateDirectory($job)
        Copy-Item -LiteralPath $script:UsbScript -Destination $job
        [IO.File]::WriteAllText((Join-Path $job 'usb-request.json'), '{}')
        $name = "Cl$([char]0xE9) $([char]0x424)$([char]0x5C0F)"
        # Functions take precedence over the Storage cmdlets, so no real disk is read.
        $command = @"
`$ProgressPreference = 'SilentlyContinue'
function Get-Disk { [pscustomobject]@{ Number=7; FriendlyName='$name'; SerialNumber='S'; UniqueId='U'; Path='P'; Size=16GB; BusType='USB'; IsBoot=`$false; IsSystem=`$false; IsReadOnly=`$false; IsOffline=`$false } }
function Get-Partition { }
function Get-Volume { }
& '$(Join-Path $job 'Write-Usb.ps1')' -RequestFile '$(Join-Path $job 'usb-request.json')' -Operation List
"@
        $start = New-Object Diagnostics.ProcessStartInfo (Join-Path $PSHOME 'powershell.exe')
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $process = [Diagnostics.Process]::Start($start)
        $bytes = New-Object IO.MemoryStream
        $process.StandardOutput.BaseStream.CopyTo($bytes)
        $process.WaitForExit()
        $process.ExitCode | Should -Be 0
        # The app reads stdout as strict UTF-8, as this does.
        $output = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes.ToArray())
        $output | Should -Match ([regex]::Escape("VANTA_RESULT:{`"drives`":[{") + '.*' + [regex]::Escape("`"name`":`"$name`""))
    }
    It 'lists drives with inbox storage cmdlets despite an inherited shadow module' {
        $job = Join-Path $TestDrive 'job'
        $shadow = Join-Path $TestDrive 'modules\Storage'
        $marker = Join-Path $TestDrive 'shadow-imported.txt'
        [void][IO.Directory]::CreateDirectory($job)
        [void][IO.Directory]::CreateDirectory($shadow)
        Copy-Item -LiteralPath $script:UsbScript -Destination $job
        [IO.File]::WriteAllText((Join-Path $job 'usb-request.json'), '{}')
        [IO.File]::WriteAllText((Join-Path $shadow 'Storage.psd1'), "@{ RootModule = 'Storage.psm1'; ModuleVersion = '99.0.0'; FunctionsToExport = @('Get-Disk') }")
        [IO.File]::WriteAllText((Join-Path $shadow 'Storage.psm1'), "[IO.File]::WriteAllText('$marker', 'imported'); function Get-Disk { }")
        $savedPath = $env:PSModulePath
        try {
            $env:PSModulePath = (Split-Path $shadow -Parent) + [IO.Path]::PathSeparator + (Join-Path $PSHOME 'Modules')
            $output = & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $job 'Write-Usb.ps1') -RequestFile (Join-Path $job 'usb-request.json') -Operation List
            $LASTEXITCODE | Should -Be 0
        }
        finally { $env:PSModulePath = $savedPath }
        ($output -join "`n") | Should -Match '^VANTA_RESULT:'
        [IO.File]::Exists($marker) | Should -BeFalse
    }
}

Describe 'USB formatting interruption points' {
    BeforeEach {
        $script:Operations = [Collections.Generic.List[string]]::new()
        $script:StopAfter = ''
        $script:ReplaceAfter = ''
        Mock Assert-VantaUsbContinue {
            if ($script:StopAfter -and $script:Operations.Contains($script:StopAfter)) {
                throw [OperationCanceledException]::new('cancelled')
            }
        }
        Mock Assert-VantaUsbIdentity {
            if ($script:ReplaceAfter -and $script:Operations.Contains($script:ReplaceAfter)) {
                throw 'The USB drive changed.'
            }
            [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_Disk', 'root/Microsoft/Windows/Storage')
        }
        Mock Clear-Disk { $script:Operations.Add('clear') }
        Mock Initialize-Disk { $script:Operations.Add('initialize') }
        Mock Set-Disk { $script:Operations.Add('convert') }
        Mock New-Partition {
            $script:Operations.Add('partition')
            [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_Partition', 'root/Microsoft/Windows/Storage')
        }
        Mock Format-Volume { $script:Operations.Add('format'); [pscustomobject]@{DriveLetter='Z'} }
    }
    It 'formats only after clearing, initializing and partitioning the confirmed device' {
        (Format-VantaUsb ([pscustomobject]@{number=42}) 16GB).DriveLetter | Should -Be 'Z'
        ($script:Operations -join ',') | Should -Be 'clear,initialize,partition,format'
        Should -Invoke Assert-VantaUsbIdentity -Times 4 -Exactly
    }
    It 'starts no further destructive operation after cancellation at <After>' -ForEach @(
        @{After='clear'; Expected='clear'},
        @{After='initialize'; Expected='clear,initialize'},
        @{After='partition'; Expected='clear,initialize,partition'}
    ) {
        $script:StopAfter = $After
        { Format-VantaUsb ([pscustomobject]@{number=42}) 16GB } | Should -Throw '*cancelled*'
        ($script:Operations -join ',') | Should -Be $Expected
        Should -Invoke Format-Volume -Times 0 -Exactly
    }
    It 'starts no further destructive operation after replacement at <After>' -ForEach @(
        @{After='clear'; Expected='clear'},
        @{After='initialize'; Expected='clear,initialize'},
        @{After='partition'; Expected='clear,initialize,partition'}
    ) {
        $script:ReplaceAfter = $After
        { Format-VantaUsb ([pscustomobject]@{number=42}) 16GB } | Should -Throw '*changed*'
        ($script:Operations -join ',') | Should -Be $Expected
        Should -Invoke Format-Volume -Times 0 -Exactly
    }
    Context 'an uninitialized (RAW) disk' {
        BeforeEach {
            # A cancelled write or diskpart clean leaves the disk without a partition table.
            Mock Assert-VantaUsbIdentity {
                if ($script:ReplaceAfter -and $script:Operations.Contains($script:ReplaceAfter)) {
                    throw 'The USB drive changed.'
                }
                $disk = [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_Disk', 'root/Microsoft/Windows/Storage')
                $disk.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('PartitionStyle', [uint16]0, [Microsoft.Management.Infrastructure.CimFlags]::None))
                $disk
            }
        }
        It 'initializes it without clearing' {
            (Format-VantaUsb ([pscustomobject]@{number=42}) 16GB).DriveLetter | Should -Be 'Z'
            ($script:Operations -join ',') | Should -Be 'initialize,partition,format'
            Should -Invoke Clear-Disk -Times 0 -Exactly
            Should -Invoke Assert-VantaUsbIdentity -Times 3 -Exactly
        }
        It 'starts no further destructive operation after <Kind> at initialize' -ForEach @(
            @{Kind='cancellation'; Stop='initialize'; Replace=''; Message='*cancelled*'},
            @{Kind='replacement'; Stop=''; Replace='initialize'; Message='*changed*'}
        ) {
            $script:StopAfter = $Stop
            $script:ReplaceAfter = $Replace
            { Format-VantaUsb ([pscustomobject]@{number=42}) 16GB } | Should -Throw $Message
            ($script:Operations -join ',') | Should -Be 'initialize'
            Should -Invoke Format-Volume -Times 0 -Exactly
        }
    }
    Context 'removable media, which Clear-Disk leaves initialized' {
        It 'partitions a <Style> drive after clearing it, without initializing it again' -ForEach @(
            @{Style='MBR'; Value=1; Expected='clear,partition,format'},
            @{Style='GPT'; Value=2; Expected='clear,convert,partition,format'}
        ) {
            # A USB flash drive another tool, such as Rufus or Windows setup, already partitioned.
            Mock Assert-VantaUsbIdentity {
                $disk = [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_Disk', 'root/Microsoft/Windows/Storage')
                $disk.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('PartitionStyle', [uint16]$Value, [Microsoft.Management.Infrastructure.CimFlags]::None))
                $disk
            }
            (Format-VantaUsb ([pscustomobject]@{number=42}) 16GB).DriveLetter | Should -Be 'Z'
            ($script:Operations -join ',') | Should -Be $Expected
            Should -Invoke Initialize-Disk -Times 0 -Exactly
        }
    }
}

Describe 'Safe ejection of USB Attached SCSI storage' {
    BeforeEach {
        $script:UsbParent = 'USB\VID_0951&PID_177F\TEST'
        Mock Get-CimInstance { @([pscustomobject]@{Index=42;PNPDeviceID='SCSI\DISK\USB'},[pscustomobject]@{Index=0;PNPDeviceID='SCSI\DISK\SYSTEM'}) }
        Mock Get-PnpDeviceProperty {
            param($InstanceId,$KeyName)
            if ($KeyName -eq 'DEVPKEY_Device_Service') { return [pscustomobject]@{Data='UASPStor'} }
            if ($InstanceId -eq 'SCSI\DISK\USB') { return [pscustomobject]@{Data=$script:UsbParent} }
            return [pscustomobject]@{Data='PCI\CONTROLLER'}
        }
    }
    It 'selects the physical USB device rather than its non-removable SCSI child' {
        Get-VantaUsbEjectTarget ([pscustomobject]@{Number=42}) | Should -Be $script:UsbParent
    }
    It 'never climbs to a hub or PCI controller' {
        $script:UsbParent='USB\ROOT_HUB30\HOST'
        { Get-VantaUsbEjectTarget ([pscustomobject]@{Number=42}) } | Should -Throw '*No removable*'
    }
    It 'refuses a parent that would eject another disk too' {
        Mock Get-PnpDeviceProperty {
            param($InstanceId,$KeyName)
            if ($KeyName -eq 'DEVPKEY_Device_Service') { return [pscustomobject]@{Data='UASPStor'} }
            if ($InstanceId -notin @('SCSI\DISK\USB', 'SCSI\DISK\SYSTEM')) { throw 'Unexpected test device.' }
            return [pscustomobject]@{Data=$script:UsbParent}
        }
        { Get-VantaUsbEjectTarget ([pscustomobject]@{Number=42}) } | Should -Throw '*Another disk*'
    }
}

Describe 'USB destination safety' {
    It 'returns the volume GUID path, never a drive-letter root' {
        $volume = [pscustomobject]@{ DriveLetter='Z'; UniqueId='\\?\Volume{12345678-1234-1234-1234-123456789abc}\' }
        Get-VantaUsbTargetRoot $volume | Should -BeExactly $volume.UniqueId
    }
    It 'rejects a mutable drive-letter or malformed target path' -ForEach @('Z:\', '', '\\?\Volume{invalid}\') {
        { Get-VantaUsbTargetRoot ([pscustomobject]@{UniqueId=$_}) } | Should -Throw '*stable USB volume*'
    }
    BeforeEach {
        $script:Disk = [pscustomobject]@{ Number=42; FriendlyName='Test USB'; SerialNumber='SERIAL-A'; UniqueId='USB-A'; Path='DEVICE-A'; Size=64GB; BusType='USB'; IsBoot=$false; IsSystem=$false; IsReadOnly=$false; IsOffline=$false }
        Mock Get-Disk { $script:Disk }
        Mock Get-Partition { @() }
        # A drive that no longer matches the list is typed, so the app can send
        # the user to Refresh; the message only reaches the log.
        Mock Fail { throw "$Reason|$Message" }
        $script:Expected = Get-VantaUsbIdentity $script:Disk
    }
    It 'accepts the same eligible USB and retains its identity' {
        (Assert-VantaUsbIdentity $script:Expected).Number | Should -Be 42
    }
    It 'rejects a replacement reusing the same disk number' -ForEach @('SerialNumber','UniqueId','Path','FriendlyName') {
        $script:Disk.$_ = 'REPLACEMENT'
        { Assert-VantaUsbIdentity $script:Expected } | Should -Throw 'drive-changed|*changed*'
    }
    It 'rejects a resized or differently reported device' {
        $script:Disk.Size = 128GB
        { Assert-VantaUsbIdentity $script:Expected } | Should -Throw 'drive-changed|*changed*'
    }
    It 'rejects boot, system, read-only and offline disks' -ForEach @('IsBoot','IsSystem','IsReadOnly','IsOffline') {
        $script:Disk.$_ = $true
        { Assert-VantaUsbIdentity $script:Expected } | Should -Throw 'drive-changed|*eligible*'
    }
    It 'rejects internal disks, missing identifiers and unsupported capacities' {
        $script:Disk.BusType = 'NVMe'
        Test-VantaUsbDisk $script:Disk | Should -BeFalse
        $script:Disk.BusType = 'USB'
        $script:Disk.UniqueId = ''
        Test-VantaUsbDisk $script:Disk | Should -BeFalse
        $script:Disk.UniqueId = 'USB-A'
        $script:Disk.Size = 4GB
        Test-VantaUsbDisk $script:Disk | Should -BeFalse
        $script:Disk.Size = 3TB
        Test-VantaUsbDisk $script:Disk | Should -BeFalse
    }
    It 'fails closed if the USB disappears' {
        # Get-Disk finds no disk with that number and reports nothing.
        Mock Get-Disk { }
        { Assert-VantaUsbIdentity $script:Expected } | Should -Throw 'drive-changed|*eligible*'
        Should -Invoke Get-Disk -ParameterFilter { $ErrorAction -eq 'SilentlyContinue' }
    }
    It 'rejects a reused drive letter even when the original USB is still connected' {
        $volume = [pscustomobject]@{ DriveLetter='Z'; UniqueId='VOLUME-A' }
        Mock Get-VantaUsbVolumeId { 'VOLUME-B' }
        Mock Assert-VantaUsbIdentity { $script:Disk }
        { Assert-VantaUsbVolume $script:Expected $volume } | Should -Throw '*volume changed*'
        Mock Get-VantaUsbVolumeId { 'VOLUME-A' }
        { Assert-VantaUsbVolume $script:Expected $volume } | Should -Not -Throw
    }
    It 'refuses a source or working file stored on the target disk' {
        $file = Join-Path $TestDrive 'source.iso'
        Set-Content -LiteralPath $file -Value 'data'
        Mock Get-Partition { [pscustomobject]@{ DiskNumber=42 } }
        Mock Fail { throw "$Reason|$Message" }
        { Assert-VantaUsbPaths $script:Disk @($file) } | Should -Throw 'source-location|*Move them*'
        Mock Get-Partition { [pscustomobject]@{ DiskNumber=7 } }
        { Assert-VantaUsbPaths $script:Disk @($file) } | Should -Not -Throw
    }
    It 'refuses a drive letter with no partition behind it as a source location' {
        $file = Join-Path $TestDrive 'source.iso'
        Set-Content -LiteralPath $file -Value 'data'
        # What Get-Partition reports for a mapped network or encrypted-container drive.
        Mock Get-Partition { Write-Error -Message 'No MSFT_Partition objects found' -Category ObjectNotFound -ErrorAction Stop }
        { Assert-VantaUsbPaths $script:Disk @($file) } | Should -Throw 'source-location|*no local disk partition*'
        # Any other lookup failure isn't the user's to fix, so it stays untyped.
        Mock Get-Partition { Write-Error -Message 'Injected storage failure' -Category NotSpecified -ErrorAction Stop }
        { Assert-VantaUsbPaths $script:Disk @($file) } | Should -Throw 'Injected storage failure'
        Should -Invoke Fail -Times 1 -Exactly
    }
    It 'refuses a path through a junction but accepts a reparse point that is not a link' {
        Mock Get-Partition { [pscustomobject]@{ DiskNumber=7 } }
        Mock Fail { throw "$Reason|$Message" }
        $target = Join-Path $TestDrive 'target'
        [void][IO.Directory]::CreateDirectory($target)
        Set-Content -LiteralPath (Join-Path $target 'source.iso') -Value 'data'
        $junction = Join-Path $TestDrive 'linked'
        $null = cmd.exe /d /c mklink /J "$junction" "$target"
        try { { Assert-VantaUsbPaths $script:Disk @(Join-Path $junction 'source.iso') } | Should -Throw 'source-location|*Linked*' }
        finally { [IO.Directory]::Delete($junction) }
        # OneDrive Files On-Demand marks backed-up folders such as the Desktop this way.
        Mock Get-Item { [pscustomobject]@{ FullName='C:\Users\Someone\OneDrive\Desktop\VantaManager.exe'; Attributes=[IO.FileAttributes]'Archive, ReparsePoint'; LinkType=$null; Parent=$null } }
        { Assert-VantaUsbPaths $script:Disk @('C:\Users\Someone\OneDrive\Desktop\VantaManager.exe') } | Should -Not -Throw
    }
    Context 'the write worker' {
        BeforeAll {
            # The worker writes its manifest beside the script, and a function made from
            # a script block has no $PSScriptRoot, so load it from a file in a job folder.
            $ast = [Management.Automation.Language.Parser]::ParseFile($script:UsbScript,[ref]$null,[ref]$null)
            $worker = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-VantaUsbWorker'},$true)
            $script:Job = Join-Path $TestDrive 'write-job'
            [void][IO.Directory]::CreateDirectory($script:Job)
            [IO.File]::WriteAllText((Join-Path $script:Job 'Invoke-VantaUsbWorker.ps1'), $worker.Extent.Text, (New-Object Text.UTF8Encoding($true)))
            . (Join-Path $script:Job 'Invoke-VantaUsbWorker.ps1')
        }
        BeforeEach {
            $script:Source = Join-Path $TestDrive 'Windows.iso'
            Set-Content -LiteralPath $script:Source -Value 'fixture'
            $script:Root = '\\?\Volume{12345678-1234-1234-1234-123456789abc}\'
            $script:Destinations = [Collections.Generic.List[string]]::new()
            $script:Image = [Microsoft.Management.Infrastructure.CimInstance]::new('MSFT_DiskImage', 'root/Microsoft/Windows/Storage')
            $script:Image.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('Attached', $true, [Microsoft.Management.Infrastructure.CimFlags]::None))
            Mock Read-VantaUsbRequest { [pscustomobject]@{ drive=$script:Expected; eraseConfirmed=$true; source=$script:Source; app=$script:Source; supportedBuilds=@(26200) } }
            Mock Assert-VantaUsbIdentity { $script:Disk }
            Mock Assert-VantaUsbPaths { }
            Mock Assert-VantaUsbContinue { }
            Mock Write-VantaUsbProgress { }
            # The mocked Get-ChildItem takes -File only for a path on an existing
            # FileSystem drive, so the mounted ISO reports the test drive's letter.
            $script:MediaRoot = [IO.Path]::GetPathRoot($TestDrive)
            Mock Get-DiskImage { $script:Image }
            Mock Get-Volume { [pscustomobject]@{ DriveLetter=$script:MediaRoot.Substring(0,1) } }
            Mock Import-Module { }
            Mock Get-VantaUsbMediaInfo { [pscustomobject]@{ imagePath=($script:MediaRoot + 'sources\install.wim'); architecture=9 } }
            Mock Get-ChildItem {
                [pscustomobject]@{ FullName=($script:MediaRoot + 'setup.exe'); Length=1KB; Attributes=[IO.FileAttributes]::Archive }
                [pscustomobject]@{ FullName=($script:MediaRoot + 'sources\boot.wim'); Length=1MB; Attributes=[IO.FileAttributes]::Archive }
            }
            Mock Get-FileHash { [pscustomobject]@{ Hash='HASH' } }
            Mock Format-VantaUsb { [pscustomobject]@{ DriveLetter='Z'; UniqueId=$script:Root } }
            Mock Assert-VantaUsbVolume { }
            Mock Copy-VantaUsbFile { $script:Destinations.Add($Destination) }
            Mock Test-VantaUsbCopy { }
        }
        It 'copies to and verifies the formatted volume by its GUID path, not its drive letter' {
            # The worker reads its script parameters through dynamic scope.
            $script:RequestFile = Join-Path $script:Job 'usb-request.json'
            $script:Operation = 'Write'
            $null = Invoke-VantaUsbWorker
            # Windows can hand Z: to another volume while the copy runs.
            ($script:Destinations -join ',') | Should -BeExactly "$($script:Root)setup.exe,$($script:Root)sources\boot.wim"
            Should -Invoke Test-VantaUsbCopy -Times 1 -Exactly -ParameterFilter { $Target -ceq $script:Root }
        }
        It 'keeps the outcome when the split folder cannot be removed' {
            $script:RequestFile = Join-Path $script:Job 'usb-request.json'
            $script:Operation = 'Write'
            $script:Split = Join-Path $script:Job 'split'
            [void][IO.Directory]::CreateDirectory($script:Split)
            Mock Remove-Item { throw 'held open' } -ParameterFilter { $LiteralPath -eq $script:Split }
            # A scratch file another process still holds must not fail a verified write.
            (@(Invoke-VantaUsbWorker) -join "`n") | Should -Match '^VANTA_RESULT:.*"verified":true'
            # A cleanup failure must not replace the error in flight.
            Mock Test-VantaUsbCopy { throw 'USB verification failed: setup.exe' }
            { Invoke-VantaUsbWorker } | Should -Throw 'USB verification failed: setup.exe'
            Should -Invoke Remove-Item -Times 2 -Exactly -ParameterFilter { $LiteralPath -eq $script:Split }
        }
    }
}

Describe 'USB file copy cancellation and existing data' {
    It 'preserves the required separator for files directly on a volume GUID root' {
        $root = '\\?\Volume{12345678-1234-1234-1234-123456789abc}\'
        Get-VantaUsbParentPath ($root + 'bootmgr') | Should -Be $root
        Get-VantaUsbParentPath ($root + 'sources\boot.wim') | Should -Be ($root + 'sources\')
    }
    BeforeEach {
        Mock Assert-VantaUsbContinue { }
        $script:Source = Join-Path $TestDrive 'source.bin'
        $script:Destination = Join-Path $TestDrive 'copied.bin'
        [IO.File]::WriteAllBytes($script:Source,(New-Object byte[] (9MB)))
        if (Test-Path -LiteralPath $script:Destination) { Remove-Item -LiteralPath $script:Destination }
    }
    It 'copies every byte and flushes a verifiable file' {
        Copy-VantaUsbFile $script:Source $script:Destination
        (Get-FileHash $script:Destination).Hash | Should -Be (Get-FileHash $script:Source).Hash
    }
    It 'does not overwrite an unexpected existing destination file' {
        Set-Content -LiteralPath $script:Destination -Value 'keep'
        { Copy-VantaUsbFile $script:Source $script:Destination } | Should -Throw
        (Get-Content $script:Destination -Raw).Trim() | Should -Be 'keep'
    }
    It 'interrupts a large copy and releases the destination handle' {
        Mock Assert-VantaUsbContinue { throw [OperationCanceledException]::new('cancel') }
        { Copy-VantaUsbFile $script:Source $script:Destination } | Should -Throw '*cancel*'
        { Remove-Item -LiteralPath $script:Destination -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'USB read-back verification' {
    BeforeEach {
        Mock Assert-VantaUsbContinue { }
    }
    It 'hashes <Bytes> bytes read without the file cache exactly as Get-FileHash does' -ForEach @(
        @{Bytes=0}, @{Bytes=1}, @{Bytes=4095}, @{Bytes=4096}, @{Bytes=(9MB + 3)}
    ) {
        $path = Join-Path $TestDrive "sample-$Bytes.bin"
        $data = New-Object byte[] $Bytes
        (New-Object Random 7).NextBytes($data)
        [IO.File]::WriteAllBytes($path, $data)
        Get-VantaUsbDeviceHash $path | Should -BeExactly (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    It 'stops between chunks when cancelled and releases the file' {
        $path = Join-Path $TestDrive 'cancelled.bin'
        [IO.File]::WriteAllBytes($path, (New-Object byte[] (9MB)))
        Mock Assert-VantaUsbContinue { throw [OperationCanceledException]::new('cancel') }
        { Get-VantaUsbDeviceHash $path } | Should -Throw '*cancel*'
        { Remove-Item -LiteralPath $path -ErrorAction Stop } | Should -Not -Throw
    }
    Context 'the verify pass' {
        BeforeEach {
            $script:Target = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory((Join-Path $script:Target 'sources'))
            [IO.File]::WriteAllBytes((Join-Path $script:Target 'sources\install.swm'), [byte[]](1,2,3))
            $script:Files = @([pscustomobject]@{ relative='sources\install.swm'; bytes=3; hash='EXPECTED' })
            Mock Assert-VantaUsbVolume { }
            Mock Write-VantaUsbProgress { }
            Mock Get-FileHash { throw 'The read-back must not use the file cache.' }
        }
        It 'accepts a copy whose device read-back matches its source hash' {
            Mock Get-VantaUsbDeviceHash { 'EXPECTED' }
            { Test-VantaUsbCopy $script:Files $script:Target $null $null 3 } | Should -Not -Throw
            Should -Invoke Get-VantaUsbDeviceHash -Times 1 -Exactly -ParameterFilter { $Path -eq (Join-Path $script:Target 'sources\install.swm') }
            Should -Invoke Assert-VantaUsbVolume -Times 1 -Exactly
        }
        It 'fails on a mismatched read-back' {
            Mock Get-VantaUsbDeviceHash { 'DIFFERENT' }
            { Test-VantaUsbCopy $script:Files $script:Target $null $null 3 } | Should -Throw 'USB verification failed: sources\install.swm'
        }
        It 'fails on a truncated file without hashing it' {
            Mock Get-VantaUsbDeviceHash { 'EXPECTED' }
            $script:Files[0].bytes = 4
            { Test-VantaUsbCopy $script:Files $script:Target $null $null 4 } | Should -Throw 'USB verification failed*'
            Should -Invoke Get-VantaUsbDeviceHash -Times 0 -Exactly
        }
    }
}
