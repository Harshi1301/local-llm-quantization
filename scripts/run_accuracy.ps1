param(
    [Parameter(Mandatory=$true)][string]$Model
)

# 10-question accuracy test. Each question is a separate API call = no shared context
# (same effect as /clear). temperature 0 and seed 42 for repeatable answers.
$prefix = "Answer with only the final answer, no explanation. "
$questions = @(
    @{ q = "What is the capital of Australia?"; key = "Canberra" },
    @{ q = "What is the chemical symbol for gold?"; key = "Au" },
    @{ q = "What is 17 x 6?"; key = "102" },
    @{ q = "What is 25% of 240?"; key = "60" },
    @{ q = "Which is larger: 0.8 or 0.75?"; key = "0.8" },
    @{ q = "A farmer has 10 sheep. All but 3 run away. How many are left?"; key = "3" },
    @{ q = "What comes next: 2, 4, 8, 16, ?"; key = "32" },
    @{ q = "Anna has 3 boxes with 8 apples each. She gives away 5 apples. How many apples does she have left?"; key = "19" },
    @{ q = "A shirt costs 40 euros and is reduced by 20%. What is the new price in euros?"; key = "32" },
    @{ q = "Tom is 4 years older than Sara. Sara is 11. How old will Tom be in 5 years?"; key = "20" }
)

$outFile = Join-Path $PSScriptRoot ("accuracy_" + ($Model -replace '[:/]', '_') + ".txt")
$lines = @("Model: $Model", "Date: $(Get-Date -Format s)", "")
$score = 0
$i = 0
foreach ($item in $questions) {
    $i++
    $body = @{
        model   = $Model
        prompt  = $prefix + $item.q
        stream  = $false
        options = @{ temperature = 0; seed = 42; num_ctx = 4096 }
    } | ConvertTo-Json -Depth 5
    $r = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $body -ContentType "application/json"
    $answer = $r.response.Trim()
    # Strict matching: numbers must stand alone (key "3" must not match "13" or "3.5"),
    # words need word boundaries, and "Au" is case-sensitive (must not match "Australia").
    if ($item.key -match '^[\d.]+$') {
        $hit = $answer -match ('(?<![\d.])' + [regex]::Escape($item.key) + '(?!\d|\.\d)')
    } elseif ($item.key -ceq 'Au') {
        $hit = $answer -cmatch '\bAu\b'
    } else {
        $hit = $answer -match ('\b' + [regex]::Escape($item.key) + '\b')
    }
    if ($hit) { $score++ }
    $mark = if ($hit) { "OK " } else { "BAD" }
    $line = "Q$i [$mark] key=$($item.key) | answer: $answer"
    Write-Host $line
    $lines += $line
}
$lines += ""
$lines += "SCORE: $score / $($questions.Count)"
Write-Host "SCORE: $score / $($questions.Count)"
$lines | Set-Content -Path $outFile -Encoding utf8
Write-Host "Saved to $outFile"
