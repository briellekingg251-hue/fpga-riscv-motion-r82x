param([string]$OutDir, [int]$DurationSeconds = 120, [string]$PortName = 'COM15')
$ErrorActionPreference = 'Stop'
$port = [System.IO.Ports.SerialPort]::new($PortName,115200,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.DtrEnable = $false
$port.RtsEnable = $false
$port.Encoding = [System.Text.Encoding]::ASCII
$raw = [System.IO.StreamWriter]::new((Join-Path $OutDir 'uart.log'),$false,[System.Text.Encoding]::ASCII)
$lines = [System.IO.StreamWriter]::new((Join-Path $OutDir 'uart_timestamped.jsonl'),$false,[System.Text.Encoding]::UTF8)
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$pending = ''
try {
    $port.Open()
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'uart_open.ready'),'ready')
    while ($timer.Elapsed.TotalSeconds -lt $DurationSeconds) {
        if (Test-Path -LiteralPath (Join-Path $OutDir 'capture.stop')) { break }
        $chunk = $port.ReadExisting()
        if ($chunk.Length -gt 0) {
            $raw.Write($chunk); $raw.Flush()
            $pending += $chunk
            while ($pending.Contains("`n")) {
                $index = $pending.IndexOf("`n")
                $line = $pending.Substring(0,$index).TrimEnd("`r")
                $pending = $pending.Substring($index+1)
                $entry = @{utc=[DateTimeOffset]::UtcNow.ToString('o');monotonic_ticks=[System.Diagnostics.Stopwatch]::GetTimestamp();stopwatch_hz=[System.Diagnostics.Stopwatch]::Frequency;line=$line}
                $lines.WriteLine(($entry | ConvertTo-Json -Compress)); $lines.Flush()
            }
        }
        Start-Sleep -Milliseconds 1
    }
} finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose(); $raw.Dispose(); $lines.Dispose()
}
