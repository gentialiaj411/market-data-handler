# Comprehensive Stress Testing Script
# Tests the market data handler under various loads and conditions

param(
    [switch]$QuickTest,
    [switch]$FullTest,
    [switch]$PerformanceTest,
    [int]$Duration = 10
)

if (!$QuickTest -and !$FullTest -and !$PerformanceTest) {
    $QuickTest = $true
}

Write-Host "=== Market Data Handler Stress Testing ===" -ForegroundColor Green
Write-Host ""

$resultsDir = "stress_test_results"
if (!(Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$summaryFile = "$resultsDir\stress_test_summary_$timestamp.txt"

function Run-Test {
    param(
        [string]$Name,
        [int]$Rate,
        [int]$Symbols = 100,
        [int]$Duration = 10
    )

    Write-Host "Running test: $Name (Rate: $Rate msg/sec, Symbols: $Symbols, Duration: ${Duration}s)" -ForegroundColor Yellow

    $result = & ".\scripts\end_to_end_benchmark.ps1" -Rate $Rate -Symbols $Symbols -Duration $Duration

    # Extract metrics from output
    $throughput = 0
    $avgLatency = 0
    $p99Latency = 0

    foreach ($line in ($result -split "`n")) {
        if ($line -match "Throughput: ([\d.]+) msg/sec") {
            $throughput = [double]$Matches[1]
        }
        if ($line -match "Avg Latency: ([\d.]+) μs") {
            $avgLatency = [double]$Matches[1]
        }
        if ($line -match "P99 Latency: ([\d.]+) μs") {
            $p99Latency = [double]$Matches[1]
        }
    }

    return @{
        Name = $Name
        Rate = $Rate
        Symbols = $Symbols
        Duration = $Duration
        Throughput = $throughput
        AvgLatency = $avgLatency
        P99Latency = $p99Latency
    }
}

$allResults = @()

if ($QuickTest) {
    Write-Host "Running QUICK stress test..." -ForegroundColor Cyan

    # Basic functionality test
    $allResults += Run-Test -Name "Basic_100K" -Rate 100000 -Duration 5

    # Moderate load test
    $allResults += Run-Test -Name "Moderate_500K" -Rate 500000 -Duration 5

    # High load test
    $allResults += Run-Test -Name "High_Load_1M" -Rate 1000000 -Duration 5
}

if ($FullTest) {
    Write-Host "Running FULL stress test..." -ForegroundColor Cyan

    # Low load tests
    $allResults += Run-Test -Name "Low_Load_50K" -Rate 50000 -Duration $Duration
    $allResults += Run-Test -Name "Low_Load_100K" -Rate 100000 -Duration $Duration

    # Medium load tests
    $allResults += Run-Test -Name "Medium_Load_250K" -Rate 250000 -Duration $Duration
    $allResults += Run-Test -Name "Medium_Load_500K" -Rate 500000 -Duration $Duration

    # High load tests
    $allResults += Run-Test -Name "High_Load_750K" -Rate 750000 -Duration $Duration
    $allResults += Run-Test -Name "High_Load_1M" -Rate 1000000 -Duration $Duration

    # Maximum load test
    $allResults += Run-Test -Name "Max_Load_2M" -Rate 2000000 -Duration $Duration
}

if ($PerformanceTest) {
    Write-Host "Running PERFORMANCE stress test..." -ForegroundColor Cyan

    # Test with different symbol counts
    $allResults += Run-Test -Name "Perf_1M_50_Symbols" -Rate 1000000 -Symbols 50 -Duration $Duration
    $allResults += Run-Test -Name "Perf_1M_100_Symbols" -Rate 1000000 -Symbols 100 -Duration $Duration
    $allResults += Run-Test -Name "Perf_1M_200_Symbols" -Rate 1000000 -Symbols 200 -Duration $Duration

    # Test sustained load
    $allResults += Run-Test -Name "Sustained_800K_30s" -Rate 800000 -Duration 30

    # Test burst patterns
    $allResults += Run-Test -Name "Burst_1_5M" -Rate 1500000 -Duration 5
}

# Generate summary report
Write-Host "`nGenerating stress test summary..." -ForegroundColor Green

"==================================================" | Out-File -FilePath $summaryFile
"COMPREHENSIVE STRESS TEST RESULTS" | Out-File -FilePath $summaryFile -Append
"==================================================" | Out-File -FilePath $summaryFile -Append
"Test Run: $timestamp" | Out-File -FilePath $summaryFile -Append
"" | Out-File -FilePath $summaryFile -Append

"DETAILED RESULTS:" | Out-File -FilePath $summaryFile -Append
"-----------------" | Out-File -FilePath $summaryFile -Append

foreach ($result in $allResults) {
    "Test: $($result.Name)" | Out-File -FilePath $summaryFile -Append
    "  Target Rate: $($result.Rate) msg/sec" | Out-File -FilePath $summaryFile -Append
    "  Actual Throughput: $($result.Throughput) msg/sec" | Out-File -FilePath $summaryFile -Append
    "  Throughput Efficiency: $(([math]::Round($result.Throughput / $result.Rate * 100, 1)))%" | Out-File -FilePath $summaryFile -Append
    "  Avg Latency: $($result.AvgLatency) μs" | Out-File -FilePath $summaryFile -Append
    "  P99 Latency: $($result.P99Latency) μs" | Out-File -FilePath $summaryFile -Append
    "" | Out-File -FilePath $summaryFile -Append
}

"SUMMARY STATISTICS:" | Out-File -FilePath $summaryFile -Append
"-------------------" | Out-File -FilePath $summaryFile -Append

$avgEfficiency = ($allResults | ForEach-Object { $_.Throughput / $_.Rate } | Measure-Object -Average).Average * 100
$maxThroughput = ($allResults | Measure-Object -Property Throughput -Maximum).Maximum
$avgLatency = ($allResults | Measure-Object -Property AvgLatency -Average).Average
$maxLatency = ($allResults | Measure-Object -Property AvgLatency -Maximum).Maximum

"Average Throughput Efficiency: $([math]::Round($avgEfficiency, 1))%" | Out-File -FilePath $summaryFile -Append
"Maximum Throughput: $([math]::Round($maxThroughput, 0)) msg/sec" | Out-File -FilePath $summaryFile -Append
"Average Latency: $([math]::Round($avgLatency, 2)) μs" | Out-File -FilePath $summaryFile -Append
"Worst Latency: $([math]::Round($maxLatency, 2)) μs" | Out-File -FilePath $summaryFile -Append

Write-Host "Stress test completed! Results saved to $summaryFile" -ForegroundColor Green
Write-Host "`n=== QUICK SUMMARY ===" -ForegroundColor Yellow
Write-Host "Average Efficiency: $([math]::Round($avgEfficiency, 1))%" -ForegroundColor White
Write-Host "Max Throughput: $([math]::Round($maxThroughput, 0)) msg/sec" -ForegroundColor White
Write-Host "Average Latency: $([math]::Round($avgLatency, 2)) μs" -ForegroundColor White
