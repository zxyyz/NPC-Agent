$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$modelDir = Join-Path $root "models\llm\Qwen3.5-4B-Q4_K_M-GGUF"
$target = Join-Path $modelDir "qwen3-5-4B-Q4_K_M.gguf"
$parts = Get-ChildItem -LiteralPath $modelDir -Filter "qwen3-5-4B-Q4_K_M.gguf.part*" |
    Sort-Object Name

if (-not $parts) {
    throw "No model parts found in $modelDir. Run 'git lfs pull' first."
}

$output = [System.IO.File]::Create($target)
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

Write-Host "Reconstructed $target"
