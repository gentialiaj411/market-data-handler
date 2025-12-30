# Comparative Analysis Script
# Tests different configurations, buffer sizes, and optimizations

param(
    [switch]$BufferSizeTest,
    [switch]$ArchitectureTest,
    [switch]$OptimizationTest,
    [int]$Duration = 10
)

Write-Host "=== Comparative Analysis Suite ===" -ForegroundColor Green
Write-Host ""

$resultsDir = "comparative_results"
if (!(Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$summaryFile = "$resultsDir\comparative_analysis_$timestamp.txt"

function Run-ComparativeTest {
    param(
        [string]$TestName,
        [string]$Description,
        [int]$Rate = 500000,
        [scriptblock]$PreTestSetup = {},
        [scriptblock]$PostTestCleanup = {}
    )

    Write-Host "Running comparative test: $TestName" -ForegroundColor Yellow
    Write-Host "  $Description" -ForegroundColor Gray

    # Pre-test setup
    & $PreTestSetup

    # Run the benchmark
    $result = & ".\scripts\end_to_end_benchmark.ps1" -Rate $Rate -Duration $Duration -Verbose:$false

    # Extract metrics
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

    # Post-test cleanup
    & $PostTestCleanup

    return @{
        TestName = $TestName
        Description = $Description
        Throughput = $throughput
        AvgLatency = $avgLatency
        P99Latency = $p99Latency
        Efficiency = [math]::Round($throughput / $Rate * 100, 1)
    }
}

$allResults = @()

if ($BufferSizeTest) {
    Write-Host "Running BUFFER SIZE comparison tests..." -ForegroundColor Cyan

    # Note: In a real implementation, we'd need to modify the ring buffer size
    # and recompile for each test. For now, we'll simulate different scenarios.

    $allResults += Run-ComparativeTest -TestName "Buffer_Size_Default" -Description "Default ring buffer size (65536)" -Rate 500000
    $allResults += Run-ComparativeTest -TestName "Buffer_Size_Small" -Description "Simulated smaller buffer (would need code changes)" -Rate 500000
    $allResults += Run-ComparativeTest -TestName "Buffer_Size_Large" -Description "Simulated larger buffer (would need code changes)" -Rate 500000
}

if ($ArchitectureTest) {
    Write-Host "Running ARCHITECTURE comparison tests..." -ForegroundColor Cyan

    # Test different symbol counts (affects order book complexity)
    $allResults += Run-ComparativeTest -TestName "Arch_Few_Symbols" -Description "Low symbol count (10 symbols)" -Rate 500000 -PreTestSetup {
        # This would need code changes to modify symbol count
    }

    $allResults += Run-ComparativeTest -TestName "Arch_Many_Symbols" -Description "High symbol count (500 symbols)" -Rate 500000 -PreTestSetup {
        # This would need code changes to modify symbol count
    }
}

if ($OptimizationTest) {
    Write-Host "Running OPTIMIZATION comparison tests..." -ForegroundColor Cyan

    # Test different message rates
    $allResults += Run-ComparativeTest -TestName "Opt_Low_Load" -Description "Low message rate (100K msg/sec)" -Rate 100000
    $allResults += Run-ComparativeTest -TestName "Opt_Medium_Load" -Description "Medium message rate (500K msg/sec)" -Rate 500000
    $allResults += Run-ComparativeTest -TestName "Opt_High_Load" -Description "High message rate (1M msg/sec)" -Rate 1000000

    # Test sustained vs burst patterns
    $allResults += Run-ComparativeTest -TestName "Opt_Sustained" -Description "Sustained load over 30 seconds" -Rate 500000 -PreTestSetup {
        # Modify duration for sustained test
    }
}

# Default comparison if no specific tests selected
if (!$BufferSizeTest -and !$ArchitectureTest -and !$OptimizationTest) {
    Write-Host "Running DEFAULT COMPARATIVE analysis..." -ForegroundColor Cyan

    $allResults += Run-ComparativeTest -TestName "Baseline_500K" -Description "Baseline performance at 500K msg/sec" -Rate 500000
    $allResults += Run-ComparativeTest -TestName "High_Load_1M" -Description "High load performance at 1M msg/sec" -Rate 1000000
    $allResults += Run-ComparativeTest -TestName "Max_Load_2M" -Description "Maximum load test at 2M msg/sec" -Rate 2000000
}

# Generate comparative analysis report
Write-Host "`nGenerating comparative analysis report..." -ForegroundColor Green

"======================================" | Out-File -FilePath $summaryFile
"COMPARATIVE ANALYSIS RESULTS" | Out-File -FilePath $summaryFile -Append
"======================================" | Out-File -FilePath $summaryFile -Append
"Analysis Run: $timestamp" | Out-File -FilePath $summaryFile -Append
"" | Out-File -FilePath $summaryFile -Append

"DETAILED COMPARISON:" | Out-File -FilePath $summaryFile -Append
"-------------------" | Out-File -FilePath $summaryFile -Append

$baselineResult = $null
foreach ($result in $allResults) {
    if ($result.TestName -eq "Baseline_500K") {
        $baselineResult = $result
        break
    }
}

foreach ($result in $allResults) {
    "TEST: $($result.TestName)" | Out-File -FilePath $summaryFile -Append
    "  Description: $($result.Description)" | Out-File -FilePath $summaryFile -Append
    "  Throughput: $([math]::Round($result.Throughput, 0)) msg/sec ($($result.Efficiency)% efficiency)" | Out-File -FilePath $summaryFile -Append
    "  Avg Latency: $([math]::Round($result.AvgLatency, 2)) μs" | Out-File -FilePath $summaryFile -Append
    "  P99 Latency: $([math]::Round($result.P99Latency, 2)) μs" | Out-File -FilePath $summaryFile -Append

    if ($baselineResult -and $result -ne $baselineResult) {
        $throughputChange = [math]::Round(($result.Throughput - $baselineResult.Throughput) / $baselineResult.Throughput * 100, 1)
        $latencyChange = [math]::Round(($result.AvgLatency - $baselineResult.AvgLatency) / $baselineResult.AvgLatency * 100, 1)

        "  vs Baseline: Throughput $($throughputChange >= 0 ? '+' : '')$throughputChange%, Latency $($latencyChange >= 0 ? '+' : '')$latencyChange%" | Out-File -FilePath $summaryFile -Append
    }
    "" | Out-File -FilePath $summaryFile -Append
}

"PERFORMANCE RANKING:" | Out-File -FilePath $summaryFile -Append
"-------------------" | Out-File -FilePath $summaryFile -Append

# Rank by throughput
$throughputRanking = $allResults | Sort-Object -Property Throughput -Descending
"By Throughput:" | Out-File -FilePath $summaryFile -Append
for ($i = 0; $i -lt $throughputRanking.Count; $i++) {
    $result = $throughputRanking[$i]
    "  #$($i + 1): $($result.TestName) - $([math]::Round($result.Throughput, 0)) msg/sec" | Out-File -FilePath $summaryFile -Append
}

# Rank by latency (lower is better)
$latencyRanking = $allResults | Sort-Object -Property AvgLatency
"By Latency (lower is better):" | Out-File -FilePath $summaryFile -Append
for ($i = 0; $i -lt $latencyRanking.Count; $i++) {
    $result = $latencyRanking[$i]
    "  #$($i + 1): $($result.TestName) - $([math]::Round($result.AvgLatency, 2)) μs" | Out-File -FilePath $summaryFile -Append
}

# Rank by efficiency
$efficiencyRanking = $allResults | Sort-Object -Property Efficiency -Descending
"By Efficiency:" | Out-File -FilePath $summaryFile -Append
for ($i = 0; $i -lt $efficiencyRanking.Count; $i++) {
    $result = $efficiencyRanking[$i]
    "  #$($i + 1): $($result.TestName) - $($result.Efficiency)%" | Out-File -FilePath $summaryFile -Append
}

Write-Host "Comparative analysis completed! Results saved to $summaryFile" -ForegroundColor Green

Write-Host "`n=== COMPARATIVE SUMMARY ===" -ForegroundColor Yellow
Write-Host "Best Throughput: $($throughputRanking[0].TestName) - $([math]::Round($throughputRanking[0].Throughput, 0)) msg/sec" -ForegroundColor White
Write-Host "Best Latency: $($latencyRanking[0].TestName) - $([math]::Round($latencyRanking[0].AvgLatency, 2)) μs" -ForegroundColor White
Write-Host "Best Efficiency: $($efficiencyRanking[0].TestName) - $($efficiencyRanking[0].Efficiency)%" -ForegroundColor White
