# Read-only. Prints no raw command line, cookie, password, local username, or file path.
$ErrorActionPreference = 'Stop'
$processes = @(Get-CimInstance Win32_Process -Filter "Name='vnl.exe'")
if ($processes.Count -eq 0) { Write-Output 'vnl.exe not found. Connect the original VPN first.'; exit }
foreach ($proc in $processes) {
    $cmd = [string]$proc.CommandLine
    $match = [regex]::Match($cmd, 'utmssl://([^/\s"]+)/conn\?([^&\s"]+)')
    $tokenLength = $null
    $authority = $null
    if ($match.Success) {
        $authority = $match.Groups[1].Value
        $tokenLength = $match.Groups[2].Value.Length
    }
    $connections = @(Get-NetTCPConnection -OwningProcess $proc.ProcessId -State Established -ErrorAction SilentlyContinue | ForEach-Object {
        @{remoteAddress=$_.RemoteAddress; remotePort=$_.RemotePort}
    })
    [pscustomobject]@{
        process='vnl.exe'; commandLineReadable=(-not [string]::IsNullOrWhiteSpace($cmd));
        commandLineLength=$cmd.Length; containsUtmssl=($cmd -match '(?i)utmssl://');
        containsConn=($cmd -match '/conn\?'); linkRecognized=$match.Success;
        tunnelEndpoint=$authority; tokenLength=$tokenLength; connections=$connections
    } | ConvertTo-Json -Depth 4
}
