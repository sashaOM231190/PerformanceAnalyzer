[CmdletBinding()]
param(
    [ValidatePattern('^http://(127\.0\.0\.1|localhost)(:\d+)?/$')]
    [string]$Endpoint
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$copilotHome = if ([string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
    Join-Path $env:USERPROFILE '.copilot'
}
else { $env:COPILOT_HOME }
$configPath = Join-Path $copilotHome 'mcp-config.json'
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$entry = $config.mcpServers.PSObject.Properties['performance-analyzer']
if ($null -eq $entry) { throw 'No performance-analyzer MCP registration exists for this user.' }
$registration = $entry.Value
function Protect-DiagnosticText {
    param([string]$Text)
    foreach ($variable in Get-ChildItem Env:) {
        if ($variable.Name -match 'TOKEN|SECRET|PASSWORD|API_KEY' -and $variable.Value.Length -ge 4) {
            $Text = $Text.Replace($variable.Value, '[REDACTED]')
        }
    }
    if ($registration.PSObject.Properties['env']) {
        foreach ($property in $registration.env.PSObject.Properties) {
            if ($property.Name -match 'TOKEN|SECRET|PASSWORD|API_KEY' -and ([string]$property.Value).Length -ge 4) {
                $Text = $Text.Replace([string]$property.Value, '[REDACTED]')
            }
        }
    }
    return $Text
}
$command = [string]$registration.command
if ([IO.Path]::GetFileName($command) -ine 'PerformanceAnalyzer.Mcp.exe' -or
    -not (Test-Path -LiteralPath $command -PathType Leaf)) {
    throw 'The registration must point to an existing PerformanceAnalyzer.Mcp.exe.'
}
$arguments = if ($registration.PSObject.Properties['args']) { @($registration.args) } else { @() }
$registeredEndpoint = 'http://127.0.0.1:8765/'
for ($index = 0; $index -lt $arguments.Count; $index++) {
    if ($arguments[$index] -eq '--endpoint' -and $index + 1 -lt $arguments.Count) {
        $registeredEndpoint = [string]$arguments[$index + 1]
    }
}
if ($registeredEndpoint -notmatch '^http://(127\.0\.0\.1|localhost)(:\d+)?/$') {
    throw 'The registered endpoint is not a supported HTTP loopback URL.'
}
if (-not $Endpoint) { $Endpoint = $registeredEndpoint }
Write-Host "Configuration: $configPath"
Write-Host "MCP executable: $command"
$stream = [IO.File]::OpenRead($command)
$sha = [Security.Cryptography.SHA256]::Create()
try {
    Write-Host "MCP SHA256: $([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', ''))"
}
finally {
    $stream.Dispose()
    $sha.Dispose()
}
Write-Host "Registered endpoint: $registeredEndpoint"
Write-Host "Dashboard endpoint to test: $Endpoint"
if ($Endpoint -ne $registeredEndpoint) {
    Write-Warning 'The dashboard and registered MCP endpoints differ.'
}
foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY')) {
    $configured = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))
    Write-Host "$name configured: $configured"
}
$failed = $false
try {
    $response = Invoke-WebRequest -Uri ($Endpoint + 'api/metadata') -UseBasicParsing -TimeoutSec 15
    $metadata = $response.Content | ConvertFrom-Json
    Write-Host "Direct metadata API: HTTP $($response.StatusCode); $(@($metadata.Counters).Count) counters."
}
catch {
    $failed = $true
    Write-Warning (Protect-DiagnosticText "Direct metadata API failed: $($_.Exception.Message)")
}

$startInfo = New-Object Diagnostics.ProcessStartInfo
$startInfo.FileName = $command
# The MCP executable accepts only simple option/value arguments, without shell evaluation.
foreach ($argument in $arguments) {
    if ([string]$argument -match '["\r\n]') { throw 'Unsupported quoting in the registered MCP arguments.' }
}
$startInfo.Arguments = ($arguments | ForEach-Object { '"' + [string]$_ + '"' }) -join ' '
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
if ($registration.PSObject.Properties['env']) {
    foreach ($property in $registration.env.PSObject.Properties) {
        $startInfo.EnvironmentVariables[$property.Name] = [string]$property.Value
    }
}
$process = New-Object Diagnostics.Process
$process.StartInfo = $startInfo
$started = $false
$stderr = $null
$requestId = 0
function Invoke-McpRequest {
    param([string]$Method, [object]$Parameters)
    $script:requestId++
    $id = $script:requestId
    $request = @{ jsonrpc = '2.0'; id = $id; method = $Method; params = $Parameters }
    $process.StandardInput.WriteLine(($request | ConvertTo-Json -Depth 20 -Compress))
    $process.StandardInput.Flush()
    $deadline = [datetime]::UtcNow.AddSeconds(45)
    while ([datetime]::UtcNow -lt $deadline) {
        $line = $process.StandardOutput.ReadLineAsync()
        $remaining = [Math]::Max(1, [int]($deadline - [datetime]::UtcNow).TotalMilliseconds)
        if (-not $line.Wait($remaining)) { throw "MCP $Method timed out." }
        if ($null -eq $line.Result) { throw "MCP exited before responding to $Method." }
        $message = $line.Result | ConvertFrom-Json
        if ($message.PSObject.Properties['id'] -and $message.id -eq $id) {
            if ($message.PSObject.Properties['error']) {
                throw "MCP protocol error: $($message.error.message)"
            }
            return $message.result
        }
    }
    throw "MCP $Method timed out."
}
try {
    if (-not $process.Start()) { throw 'MCP process did not start.' }
    $started = $true
    $stderr = $process.StandardError.ReadToEndAsync()
    Invoke-McpRequest 'initialize' @{
        protocolVersion = '2024-11-05'
        capabilities = @{}
        clientInfo = @{ name = 'performance-analyzer-connection-diagnostic'; version = '1.0' }
    } | Out-Null
    $process.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
    $process.StandardInput.Flush()
    foreach ($tool in @('get_server_status', 'get_capture_overview', 'get_capture_health', 'get_coach_status', 'get_coach_targets')) {
        $result = Invoke-McpRequest 'tools/call' @{ name = $tool; arguments = @{} }
        if ($result.PSObject.Properties['isError'] -and $result.isError) {
            $failed = $true
            $message = @($result.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ' '
            Write-Warning (Protect-DiagnosticText "${tool}: $message")
            break
        }
        Write-Host "${tool}: succeeded."
    }
}
catch {
    $failed = $true
    Write-Warning (Protect-DiagnosticText "MCP diagnostic failed: $($_.Exception.Message)")
}
finally {
    if ($started) {
        if (-not $process.HasExited) {
            $process.StandardInput.Close()
            if (-not $process.WaitForExit(3000)) {
                $process.Kill()
                $process.WaitForExit()
            }
        }
        if ($null -ne $stderr -and $stderr.Wait(5000) -and -not [string]::IsNullOrWhiteSpace($stderr.Result)) {
            Write-Host 'MCP stderr (underlying exception, if any):'
            Write-Host (Protect-DiagnosticText $stderr.Result)
        }
    }
    $process.Dispose()
}
Write-Host 'Diagnostic only: no registration, skill, package or capture files were changed.'
if ($failed) { throw 'Connection diagnostic detected a failure. Review the MCP stderr exception above.' }
