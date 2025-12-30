# End-to-End Benchmark Script for Real Metrics
# This script runs the actual feed simulator and market handler together
# to get REAL end-to-end performance metrics (not just ring buffer benchmarks)

param(
    [int]$Rate = 1000000,      # Messages per second
    [int]$Duration = 30,       # Test duration in seconds
    [int]$Symbols = 100,       # Number of symbols to simulate
    [string]$Multicast = "239.255.0.1",
    [int]$Port = 5000,
    [switch]$Verbose
)

Write-Host "=== REAL End-to-End Market Data Handler Benchmark ===" -ForegroundColor Green
Write-Host "Rate: $Rate msg/sec, Duration: $Duration sec, Symbols: $Symbols" -ForegroundColor Yellow
Write-Host ""

# Create results directory
$resultsDir = "benchmark_results"
if (!(Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$resultFile = "$resultsDir\end_to_end_$timestamp.txt"

# Start the market handler in background
Write-Host "Starting market handler..." -ForegroundColor Cyan
$handlerJob = Start-Job -ScriptBlock {
    param($multicast, $port, $duration)
    cd $using:PWD
    .\market_handler.exe --multicast $multicast --port $port --duration $duration 2>&1
} -ArgumentList $Multicast, $Port, $Duration

# Give handler time to start
Start-Sleep -Seconds 2

# Start the feed simulator
Write-Host "Starting feed simulator..." -ForegroundColor Cyan
$simulatorOutput = & .\feed_simulator.exe --multicast $Multicast --port $Port --rate $Rate --symbols $Symbols --duration $Duration 2>&1

# Wait for handler to complete
Write-Host "Waiting for handler to complete processing..." -ForegroundColor Cyan
$handlerOutput = Receive-Job -Job $handlerJob -Wait

# Save results
Write-Host "Saving benchmark results to $resultFile..." -ForegroundColor Green

"========================================" | Out-File -FilePath $resultFile
"REAL END-TO-END BENCHMARK RESULTS" | Out-File -FilePath $resultFile -Append
"========================================" | Out-File -FilePath $resultFile -Append
"Timestamp: $timestamp" | Out-File -FilePath $resultFile -Append
"Configuration:" | Out-File -FilePath $resultFile -Append
"  Rate: $Rate msg/sec" | Out-File -FilePath $resultFile -Append
"  Duration: $Duration seconds" | Out-File -FilePath $resultFile -Append
"  Symbols: $Symbols" | Out-File -FilePath $resultFile -Append
"  Multicast: $Multicast" | Out-File -FilePath $resultFile -Append
"  Port: $Port" | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"FEED SIMULATOR OUTPUT:" | Out-File -FilePath $resultFile -Append
$simulatorOutput | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"MARKET HANDLER OUTPUT:" | Out-File -FilePath $resultFile -Append
$handlerOutput | Out-File -FilePath $resultFile -Append

Write-Host "Benchmark completed! Results saved to $resultFile" -ForegroundColor Green

if ($Verbose) {
    Write-Host "`n=== SIMULATOR OUTPUT ===" -ForegroundColor Yellow
    $simulatorOutput

    Write-Host "`n=== HANDLER OUTPUT ===" -ForegroundColor Yellow
    $handlerOutput
}

Write-Host "`n=== QUICK SUMMARY ===" -ForegroundColor Green
# Extract key metrics from handler output
$handlerLines = $handlerOutput -split "`n"
foreach ($line in $handlerLines) {
    if ($line -match "Throughput:\s+([\d.]+) msg/sec") {
        Write-Host "Throughput: $($Matches[1]) msg/sec" -ForegroundColor White
    }
    if ($line -match "Avg latency:\s+(\d+)ns") {
        $avgNs = [int]$Matches[1]
        $avgUs = $avgNs / 1000
        Write-Host "Avg Latency: $($avgUs.ToString("F2")) μs" -ForegroundColor White
    }
    if ($line -match "P99 latency:\s+(\d+)ns") {
        $p99Ns = [int]$Matches[1]
        $p99Us = $p99Ns / 1000
        Write-Host "P99 Latency: $($p99Us.ToString("F2")) μs" -ForegroundColor White
    }
}
