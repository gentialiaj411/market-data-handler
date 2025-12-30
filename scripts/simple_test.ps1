# Simple synchronous test to get real metrics

Write-Host "=== SIMPLE MARKET DATA HANDLER TEST ===" -ForegroundColor Green

# Start market handler in background
$handlerJob = Start-Job -ScriptBlock {
    cd "c:\Users\13059\Downloads\MiniVector\market-data-handler"
    .\market_handler.exe --duration 5
} -ArgumentList $null

Start-Sleep -Seconds 1

# Start feed simulator
Write-Host "Starting feed simulator..." -ForegroundColor Cyan
& .\feed_simulator.exe --rate 500000 --duration 5

# Wait for handler to finish
Write-Host "Waiting for handler to complete..." -ForegroundColor Cyan
$handlerOutput = Receive-Job -Job $handlerJob -Wait

Write-Host "`n=== HANDLER OUTPUT ===" -ForegroundColor Yellow
$handlerOutput

# Extract metrics
$throughput = 0
$avgLatency = 0
$p99Latency = 0

foreach ($line in ($handlerOutput -split "`n")) {
    if ($line -match "Throughput:\s+([\d.]+) msg/sec") {
        $throughput = [double]$Matches[1]
    }
    if ($line -match "Avg latency:\s+(\d+)ns") {
        $avgLatency = [double]$Matches[1] / 1000  # Convert to μs
    }
    if ($line -match "P99 latency:\s+(\d+)ns") {
        $p99Latency = [double]$Matches[1] / 1000  # Convert to μs
    }
}

Write-Host "`n=== EXTRACTED METRICS ===" -ForegroundColor Green
Write-Host "Throughput: $([math]::Round($throughput, 0)) msg/sec" -ForegroundColor White
Write-Host "Avg Latency: $([math]::Round($avgLatency, 2)) μs" -ForegroundColor White
Write-Host "P99 Latency: $([math]::Round($p99Latency, 2)) μs" -ForegroundColor White
