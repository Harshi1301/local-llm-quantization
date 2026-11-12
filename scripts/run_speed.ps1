param(
    [Parameter(Mandatory=$true)][string]$Model,
    [int]$Runs = 3
)

# Speed + RAM test. Prints Ollama's own metrics, same names as `ollama run --verbose`.
# Same prompt as the earlier manual tests, temperature 0, seed 42.
# Each run is a separate API call = no shared context (same effect as /clear).
$prompt = "List the eight planets of the solar system in order from the Sun, and give one short fact about each."
$outFile = Join-Path $PSScriptRoot ("speed_" + ($Model -replace '[:/]', '_') + ".txt")
$ver = (Invoke-RestMethod -Uri "http://localhost:11434/api/version" -Method Get).version
$lines = @("Model: $Model", "Ollama version: $ver", "Date: $(Get-Date -Format s)", "")
$rates = @()

function Sec($ns) { [math]::Round($ns / 1e9, 3) }

for ($i = 1; $i -le $Runs; $i++) {
    $body = @{
        model   = $Model
        prompt  = $prompt
        stream  = $false
        options = @{ temperature = 0; seed = 42; num_ctx = 4096 }
    } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json"

    # Ollama's native fields (durations are in nanoseconds; rates are count / seconds)
    $promptRate = [math]::Round($r.prompt_eval_count / ($r.prompt_eval_duration / 1e9), 2)
    $evalRate   = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 2)
    $rates += $evalRate

    $block = @(
        "--- Run $i ---",
        "total duration:       $(Sec $r.total_duration) s",
        "load duration:        $(Sec $r.load_duration) s",
        "prompt eval count:    $($r.prompt_eval_count) token(s)",
        "prompt eval duration: $(Sec $r.prompt_eval_duration) s",
        "prompt eval rate:     $promptRate tokens/s",
        "eval count:           $($r.eval_count) token(s)",
        "eval duration:        $(Sec $r.eval_duration) s",
        "eval rate:            $evalRate tokens/s"
    )
    $block | ForEach-Object { Write-Host $_ }
    $lines += $block
    $lines += ""

    if ($i -eq 1) {
        # RAM used by the loaded model (same info as `ollama ps`)
        $ps = Invoke-RestMethod -Uri "http://localhost:11434/api/ps" -Method Get
        $m = $ps.models | Where-Object { $_.name -like "$Model*" } | Select-Object -First 1
        if ($m) {
            $ramGB = [math]::Round($m.size / 1e9, 2)
            $gpuGB = [math]::Round($m.size_vram / 1e9, 2)
            $ctx = if ($m.context_length) { $m.context_length } else { "n/a" }
            $psLine = "Loaded model size in memory: $ramGB GB (of which GPU/VRAM: $gpuGB GB) | context length: $ctx"
        } else {
            $psLine = "Could not read model memory from /api/ps"
        }
        Write-Host $psLine
        $lines += $psLine
        $lines += ""
    }
}

$avg = [math]::Round(($rates | Measure-Object -Average).Average, 2)
$sd = 0
if ($rates.Count -gt 1) {
    $sumSq = 0
    foreach ($x in $rates) { $sumSq += [math]::Pow($x - $avg, 2) }
    $sd = [math]::Round([math]::Sqrt($sumSq / ($rates.Count - 1)), 2)
}
$summary = "AVERAGE eval rate: $avg tokens/s (+- $sd) over $($rates.Count) runs"
Write-Host $summary
$lines += $summary
$lines | Set-Content -Path $outFile -Encoding utf8
Write-Host "Saved to $outFile"
