# Build and push JHenTai Docker image (tag x.y.z-hhh). Run from repo root or any path.
# Prerequisites: docker login
# Env: DOCKERHUB_USERNAME (default hemumoe)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$verLine = (Select-String -Path (Join-Path $Root 'pubspec.yaml') -Pattern '^version:\s*(.+)$' | Select-Object -First 1).Matches.Groups[1].Value.Trim()
$full = $verLine -replace '\s', ''
$semver = ($full -split '\+')[0]
$build = ($full -split '\+')[1]
if (-not $build) { $build = '0' }

$frPath = Join-Path $Root 'docker\fork_revision'
if (Test-Path $frPath) {
    $fr = (Get-Content $frPath -Raw).Trim() -replace '\s', ''
} else {
    $fr = $build
}

$frNum = 0
if (-not [int]::TryParse($fr, [ref]$frNum) -or $frNum -lt 0 -or $frNum -gt 4095) {
    throw "docker/fork_revision must be decimal 0-4095, got: $fr"
}

$hhh = '{0:x3}' -f $frNum
$user = if ($env:DOCKERHUB_USERNAME) { $env:DOCKERHUB_USERNAME } else { 'hemumoe' }
$image = "${user}/jhentai"
$tag = "${semver}-${hhh}"

Write-Host "Image: ${image}:${tag} (fork_revision=$frNum -> 0x$hhh)"
docker build -t "${image}:${tag}" $Root
docker push "${image}:${tag}"
Write-Host "Pushed ${image}:${tag}"
