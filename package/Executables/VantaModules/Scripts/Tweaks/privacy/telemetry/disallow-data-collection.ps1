# Companion of disallow-data-collection.psd1: removes Vanta's fixed DiagTrack log-file
# sets through Vanta.Privacy while the install owns the machine.
$ErrorActionPreference = 'Stop'

Import-VantaModule -Name Vanta.Privacy
Clear-VantaTelemetryLogFiles
