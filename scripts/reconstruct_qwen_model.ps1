$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$modelDir = Join-Path $root "models\llm\Qwen3.5-4B-Q4_K_M-GGUF"
$target = Join-Path $modelDir "qwen3-5-4B-Q4_K_M.gguf"
$expectedHash = "DE8E96CD0D0C358487091AAAED1346BC02E61DA3D4B412C833662702E233E78C"
$expectedSize = 2707514144

function Get-ModelParts {
    Get-ChildItem -LiteralPath $modelDir -Filter "qwen3-5-4B-Q4_K_M.gguf.part*" |
        Sort-Object Name
}

function Test-LfsPointer {
    param([Parameter(Mandatory)][IO.FileInfo]$File)

    if ($File.Length -gt 1024) { return $false }
    $head = Get-Content -LiteralPath $File.FullName -TotalCount 1 -ErrorAction SilentlyContinue
    return $head -eq "version https://git-lfs.github.com/spec/v1"
}

if (Test-Path -LiteralPath $target) {
    $targetFile = Get-Item -LiteralPath $target
    if ($targetFile.Length -eq $expectedSize) {
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($hash -eq $expectedHash) {
            Write-Host "Model already reconstructed: $target"
            exit 0
        }
    }

    Write-Host "Existing model file is incomplete or does not match the expected hash. Rebuilding..."
}

$parts = @(Get-ModelParts)

if (-not $parts) {
    throw "No model parts found in $modelDir. Run 'git lfs pull' first."
}

if ($parts | Where-Object { Test-LfsPointer $_ }) {
    if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
        throw "Model parts are Git LFS pointers, but git.exe was not found. Install Git LFS, then run 'git lfs pull'."
    }

    Write-Host "Fetching model parts with Git LFS..."
    Push-Location $root
    try {
        git lfs pull
        if ($LASTEXITCODE -ne 0) {
            throw "git lfs pull failed. Install Git LFS or check your network connection, then run start.bat again."
        }
    }
    finally {
        Pop-Location
    }

    $parts = @(Get-ModelParts)
    if ($parts | Where-Object { Test-LfsPointer $_ }) {
        throw "Model parts are still Git LFS pointers after 'git lfs pull'. Check that Git LFS is installed and available."
    }
}

$actualSize = ($parts | Measure-Object -Property Length -Sum).Sum
if ($actualSize -ne $expectedSize) {
    throw "Model parts have unexpected total size: $actualSize bytes. Expected $expectedSize bytes."
}

$tempTarget = "$target.tmp"
$output = [System.IO.File]::Create($tempTarget)
try {
    foreach ($part in $parts) {
        Write-Host "Appending $($part.Name)"
        $input = [System.IO.File]::OpenRead($part.FullName)
        try {
            $input.CopyTo($output)
        }
        finally {
            $input.Dispose()
        }
    }
}
finally {
    $output.Dispose()
}

$hash = (Get-FileHash -LiteralPath $tempTarget -Algorithm SHA256).Hash
if ($hash -ne $expectedHash) {
    Remove-Item -LiteralPath $tempTarget -Force -ErrorAction SilentlyContinue
    throw "Reconstructed model hash mismatch: $hash"
}

Move-Item -LiteralPath $tempTarget -Destination $target -Force
Write-Host "Reconstructed $target"
