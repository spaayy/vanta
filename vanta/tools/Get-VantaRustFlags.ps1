# Flags de build do Vanta: CRT estático e caminhos locais removidos dos binários (o perfil do host não vaza).
# Devolve o valor para CARGO_ENCODED_RUSTFLAGS (separador 0x1f: o caminho do perfil pode ter espaço).
param([Parameter(Mandatory)][string]$Repo)
$home_ = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
$flags = @('-C', 'target-feature=+crt-static', '-C', 'link-arg=/PDBALTPATH:%_PDB%')
if ($home_) { $flags += "--remap-path-prefix=$($home_.TrimEnd('\', '/'))=/vanta-home" }
$flags += "--remap-path-prefix=$($Repo.TrimEnd('\', '/'))=/vanta-src"
$flags -join [char]0x1f
