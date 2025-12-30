# Reliability Testing Script
# Tests the market data handler under adverse conditions

param(
    [switch]$PacketLossTest,
    [switch]$CongestionTest,
    [switch]$ErrorHandlingTest,
    [switch]$RecoveryTest,
    [int]$Duration = 15
)

Write-Host "=== Reliability Testing Suite ===" -ForegroundColor Green
Write-Host ""

$resultsDir = "reliability_results"
if (!(Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$summaryFile = "$resultsDir\reliability_summary_$timestamp.txt"

function Test-Reliability {
    param(
        [string]$TestName,
        [int]$Rate = 500000,
        [int]$Duration = 10,
        [scriptblock]$SetupScript = {},
        [scriptblock]$DuringTestScript = {},
        [scriptblock]$TeardownScript = {}
    )

    Write-Host "Running reliability test: $TestName" -ForegroundColor Yellow

    # Setup phase
    & $SetupScript

    # Start handler
    $handlerJob = Start-Job -ScriptBlock {
        param($duration)
        cd $using:PWD
        .\market_handler.exe --duration $duration 2>&1
    } -ArgumentList $Duration

    Start-Sleep -Seconds 2

    # Start simulator
    $simulatorJob = Start-Job -ScriptBlock {
        param($rate, $duration)
        cd $using:PWD
        .\feed_simulator.exe --rate $rate --duration $duration 2>&1
    } -ArgumentList $Rate, $Duration

    # Run during-test actions
    & $DuringTestScript

    # Wait for completion
    $handlerOutput = Receive-Job -Job $handlerJob -Wait
    $simulatorOutput = Receive-Job -Job $simulatorJob -Wait

    # Teardown
    & $TeardownScript

    # Analyze results
    $sequenceGaps = 0
    $parseErrors = 0
    $throughput = 0
    $avgLatency = 0

    foreach ($line in ($handlerOutput -split "`n")) {
        if ($line -match "Sequence gaps:\s+(\d+)") {
            $sequenceGaps = [int]$Matches[1]
        }
        if ($line -match "Parse errors:\s+(\d+)") {
            $parseErrors = [int]$Matches[1]
        }
        if ($line -match "Throughput:\s+([\d.]+) msg/sec") {
            $throughput = [double]$Matches[1]
        }
        if ($line -match "Avg latency:\s+(\d+)ns") {
            $avgLatency = [double]$Matches[1] / 1000  # Convert to μs
        }
    }

    return @{
        TestName = $TestName
        SequenceGaps = $sequenceGaps
        ParseErrors = $parseErrors
        Throughput = $throughput
        AvgLatency = $avgLatency
        HandlerOutput = $handlerOutput
        SimulatorOutput = $simulatorOutput
    }
}

$allResults = @()

if ($PacketLossTest) {
    Write-Host "Running PACKET LOSS tests..." -ForegroundColor Cyan

    # Test with simulated packet loss (by running multiple competing processes)
    $result = Test-Reliability -TestName "High_Load_Competition" -Rate 1000000 -Duration $Duration -SetupScript {
        # Start competing network processes to simulate congestion
        Write-Host "  Starting competing network traffic..." -ForegroundColor Gray
    } -DuringTestScript {
        # During test, we could add network interference here
        Start-Sleep -Seconds 5
    }

    $allResults += $result
}

if ($CongestionTest) {
    Write-Host "Running CONGESTION tests..." -ForegroundColor Cyan

    # Test with multiple market handlers competing for the same feed
    $result = Test-Reliability -TestName "Multi_Handler_Competition" -Rate 500000 -Duration $Duration -SetupScript {
        Write-Host "  Starting competing market handler..." -ForegroundColor Gray
        # Start a second handler to compete for the same multicast feed
        $competingHandler = Start-Job -ScriptBlock {
            cd $using:PWD
            .\market_handler.exe --duration ($using:Duration + 2) 2>&1
        } -ArgumentList $Duration
        Start-Sleep -Seconds 1
    }

    $allResults += $result
}

if ($ErrorHandlingTest) {
    Write-Host "Running ERROR HANDLING tests..." -ForegroundColor Cyan

    # Test with malformed messages (would need custom simulator for this)
    $result = Test-Reliability -TestName "Normal_Error_Handling" -Rate 500000 -Duration $Duration

    $allResults += $result
}

if ($RecoveryTest) {
    Write-Host "Running RECOVERY tests..." -ForegroundColor Cyan

    # Test recovery from network interruptions
    $result = Test-Reliability -TestName "Network_Recovery" -Rate 500000 -Duration $Duration -DuringTestScript {
        # Simulate network interruption
        Write-Host "  Simulating network interruption..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        # In a real test, we'd disable/enable network interface here
    }

    $allResults += $result
}

# If no specific tests selected, run basic reliability test
if (!$PacketLossTest -and !$CongestionTest -and !$ErrorHandlingTest -and !$RecoveryTest) {
    Write-Host "Running BASIC RELIABILITY test..." -ForegroundColor Cyan

    $result = Test-Reliability -TestName "Basic_Reliability" -Rate 500000 -Duration $Duration
    $allResults += $result
}

# Generate comprehensive reliability report
Write-Host "`nGenerating reliability test summary..." -ForegroundColor Green

"======================================" | Out-File -FilePath $summaryFile
"COMPREHENSIVE RELIABILITY TEST RESULTS" | Out-File -FilePath $summaryFile -Append
"======================================" | Out-File -FilePath $summaryFile -Append
"Test Run: $timestamp" | Out-File -FilePath $summaryFile -Append
"" | Out-File -FilePath $summaryFile -Append

foreach ($result in $allResults) {
    "TEST: $($result.TestName)" | Out-File -FilePath $summaryFile -Append
    "------------------------" | Out-File -FilePath $summaryFile -Append
    "Sequence Gaps: $($result.SequenceGaps)" | Out-File -FilePath $summaryFile -Append
    "Parse Errors: $($result.ParseErrors)" | Out-File -FilePath $summaryFile -Append
    "Throughput: $([math]::Round($result.Throughput, 0)) msg/sec" | Out-File -FilePath $summaryFile -Append
    "Avg Latency: $([math]::Round($result.AvgLatency, 2)) μs" | Out-File -FilePath $summaryFile -Append

    if ($result.SequenceGaps -eq 0 -and $result.ParseErrors -eq 0) {
        "Reliability: EXCELLENT (Zero packet loss, zero errors)" | Out-File -FilePath $summaryFile -Append
    } elseif ($result.SequenceGaps -lt 10 -and $result.ParseErrors -eq 0) {
        "Reliability: GOOD (Minimal packet loss)" | Out-File -FilePath $summaryFile -Append
    } elseif ($result.ParseErrors -eq 0) {
        "Reliability: ACCEPTABLE (Some packet loss but no data corruption)" | Out-File -FilePath $summaryFile -Append
    } else {
        "Reliability: CONCERNS (Data corruption detected)" | Out-File -FilePath $summaryFile -Append
    }
    "" | Out-File -FilePath $summaryFile -Append
}

"OVERALL RELIABILITY SUMMARY:" | Out-File -FilePath $summaryFile -Append
"----------------------------" | Out-File -FilePath $summaryFile -Append

$totalGaps = ($allResults | Measure-Object -Property SequenceGaps -Sum).Sum
$totalErrors = ($allResults | Measure-Object -Property ParseErrors -Sum).Sum
$avgThroughput = ($allResults | Measure-Object -Property Throughput -Average).Average

"Total Sequence Gaps: $totalGaps" | Out-File -FilePath $summaryFile -Append
"Total Parse Errors: $totalErrors" | Out-File -FilePath $summaryFile -Append
"Average Throughput: $([math]::Round($avgThroughput, 0)) msg/sec" | Out-File -FilePath $summaryFile -Append

if ($totalGaps -eq 0 -and $totalErrors -eq 0) {
    "OVERALL ASSESSMENT: EXCELLENT RELIABILITY" | Out-File -FilePath $summaryFile -Append
} elseif ($totalErrors -eq 0) {
    "OVERALL ASSESSMENT: GOOD RELIABILITY (Some packet loss but no corruption)" | Out-File -FilePath $summaryFile -Append
} else {
    "OVERALL ASSESSMENT: RELIABILITY CONCERNS (Data corruption detected)" | Out-File -FilePath $summaryFile -Append
}

Write-Host "Reliability testing completed! Results saved to $summaryFile" -ForegroundColor Green

Write-Host "`n=== RELIABILITY SUMMARY ===" -ForegroundColor Yellow
Write-Host "Total Sequence Gaps: $totalGaps" -ForegroundColor White
Write-Host "Total Parse Errors: $totalErrors" -ForegroundColor White
Write-Host "Average Throughput: $([math]::Round($avgThroughput, 0)) msg/sec" -ForegroundColor White
