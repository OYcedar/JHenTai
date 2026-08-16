# Build and push JHenTai Docker image (tag x.y.z-hhh). Run from repo root or any path.
# Every publish bumps docker/fork_revision and refreshes README image tags first.
# Prerequisites: docker login
# Env:
#   DOCKERHUB_USERNAME (default hemumoe)
#   DOCKER_PLATFORMS (default linux/amd64,linux/arm64)
#   DOCKER_SKIP_VERSION_BUMP=1 to reuse the current docker/fork_revision.
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

if ($env:DOCKER_SKIP_VERSION_BUMP -ne '1') {
    if ($frNum -ge 4095) {
        throw 'docker/fork_revision is already 4095; cannot auto-increment'
    }
    $frNum += 1
    [System.IO.File]::WriteAllText($frPath, "$frNum`n", [System.Text.UTF8Encoding]::new($false))
}

$hhh = '{0:x3}' -f $frNum
$user = if ($env:DOCKERHUB_USERNAME) { $env:DOCKERHUB_USERNAME } else { 'hemumoe' }
$image = "${user}/jhentai"
$tag = "${semver}-${hhh}"

$docTag = "hemumoe/jhentai:${tag}"
$docFiles = @(
    'README.md',
    'README_cn.md',
    'README_kr.md',
    'DOCKER.md',
    'DOCKER_cn.md',
    'DOCKER_kr.md',
    'docker-compose.yml'
)
foreach ($file in $docFiles) {
    $path = Join-Path $Root $file
    $content = [System.IO.File]::ReadAllText($path)
    $content = [regex]::Replace($content, 'hemumoe/jhentai:\d+\.\d+\.\d+-[0-9a-f]{3}', $docTag)
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Image: ${image}:${tag} (fork_revision=$frNum -> 0x$hhh)"
Write-Host "Updated docs to ${docTag}"
$platforms = if ($env:DOCKER_PLATFORMS) { $env:DOCKER_PLATFORMS } else { 'linux/amd64,linux/arm64' }

Write-Host "Platforms: $platforms"
docker buildx build `
    --platform "$platforms" `
    --network host `
    --build-arg "JH_APP_VERSION=$full" `
    --build-arg "JH_DOCKER_TAG=$tag" `
    --build-arg "JH_FORK_REVISION=$frNum" `
    -t "${image}:${tag}" `
    -t "${image}:latest" `
    --push `
    $Root
if ($LASTEXITCODE -ne 0) {
    throw "docker buildx build failed with exit code $LASTEXITCODE"
}
Write-Host "Pushed ${image}:${tag} and ${image}:latest for $platforms"
