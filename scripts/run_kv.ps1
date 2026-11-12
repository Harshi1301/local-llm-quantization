param(
    [string]$Model = "llama3.2:3b",
    [Parameter(Mandatory=$true)][string]$KvType,      # label only: f16 | q8_0 | q4_0 (must match the server's OLLAMA_KV_CACHE_TYPE)
    [int[]]$Contexts = @(4096, 8192, 16384),
    [int]$Predict = 64
)

# Experiment B: KV-cache type vs context length.
# The Ollama SERVER must be started with OLLAMA_FLASH_ATTENTION=1 and OLLAMA_KV_CACHE_TYPE=<KvType>.
# For each context length: fill most of the context with a long prompt, generate $Predict tokens,
# record Ollama's native metrics + RAM, then unload the model so the next measurement is cold.

$base = "http://localhost:11434"
$ver = (Invoke-RestMethod -Uri "$base/api/version" -Method Get).version
$outFile = Join-Path $PSScriptRoot ("kv_" + ($Model -replace '[:/]', '_') + "_" + $KvType + ".txt")
$lines = @("Model: $Model", "KV cache type (label): $KvType", "Ollama version: $ver", "Date: $(Get-Date -Format s)", "")

function Sec($ns) { [math]::Round($ns / 1e9, 3) }

function Unload($m) {
    $b = @{ model = $m; keep_alive = 0 } | ConvertTo-Json
    Invoke-RestMethod -Uri "$base/api/generate" -Method Post -Body $b -ContentType "application/json" | Out-Null
    Start-Sleep -Seconds 5
}

function Make-Prompt($targetTokens) {
    # numbered sentences, about 18 tokens each; the numbers keep the text from being one repeated block
    $n = [int][math]::Max(1, ($targetTokens - 60) / 18)
    $sb = New-Object System.Text.StringBuilder
    for ($k = 1; $k -le $n; $k++) {
        [void]$sb.Append("Note $k : the library opened at nine in the morning and closed at five in the evening on day $k . ")
    }
    [void]$sb.Append("`nNow write a long story about this library, at least 300 words.")
    return $sb.ToString()
}

Unload $Model   # start cold

foreach ($ctx in $Contexts) {
    $prompt = Make-Prompt ($ctx - 200)
    $body = @{
        model   = $Model
        prompt  = $prompt
        stream  = $false
        options = @{ temperature = 0; seed = 42; num_ctx = $ctx; num_predict = $Predict }
    } | ConvertTo-Json -Depth 5
    Write-Host "Context $ctx : running (long prompt, this can take minutes)..."
    $r = Invoke-RestMethod -Uri "$base/api/generate" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 7200

    $promptRate = [math]::Round($r.prompt_eval_count / ($r.prompt_eval_duration / 1e9), 2)
    $evalRate   = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 2)

    $ps = Invoke-RestMethod -Uri "$base/api/ps" -Method Get
    $m = $ps.models | Where-Object { $_.name -like "$Model*" } | Select-Object -First 1
    $ramGB = if ($m) { [math]::Round($m.size / 1e9, 2) } else { "n/a" }
    $ctxSeen = if ($m -and $m.context_length) { $m.context_length } else { "n/a" }

    $block = @(
        "--- KV $KvType | num_ctx $ctx ---",
        "context length (server):  $ctxSeen",
        "RAM (model + KV cache):   $ramGB GB",
        "total duration:           $(Sec $r.total_duration) s",
        "load duration:            $(Sec $r.load_duration) s",
        "prompt eval count:        $($r.prompt_eval_count) token(s)",
        "prompt eval duration:     $(Sec $r.prompt_eval_duration) s",
        "prompt eval rate:         $promptRate tokens/s",
        "eval count:               $($r.eval_count) token(s)",
        "eval duration:            $(Sec $r.eval_duration) s",
        "eval rate:                $evalRate tokens/s",
        "answer: $($r.response.Trim())",
        ""
    )
    $block | ForEach-Object { Write-Host $_ }
    $lines += $block
    Unload $Model
}

$lines | Set-Content -Path $outFile -Encoding utf8
Write-Host "Saved to $outFile"
