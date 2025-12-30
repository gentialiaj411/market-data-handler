# Performance Monitoring Script
# Measures CPU, memory, and system resource usage during benchmarks

param(
    [int]$Rate = 1000000,
    [int]$Duration = 30,
    [int]$Symbols = 100,
    [string]$Multicast = "239.255.0.1",
    [int]$Port = 5000
)

Write-Host "=== Performance Monitoring Benchmark ===" -ForegroundColor Green
Write-Host "Monitoring system resources during $Rate msg/sec test" -ForegroundColor Yellow
Write-Host ""

$resultsDir = "performance_results"
if (!(Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$resultFile = "$resultsDir\performance_$timestamp.txt"

# Function to get system performance metrics
function Get-SystemMetrics {
    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
    $memory = Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1
    $network = Get-Counter '\Network Interface(*)\Bytes Total/sec' -SampleInterval 1 -MaxSamples 1

    return @{
        CPU = [math]::Round($cpu.CounterSamples[0].CookedValue, 2)
        Memory = [math]::Round($memory.CounterSamples[0].CookedValue, 2)
        NetworkBytesPerSec = $network.CounterSamples | ForEach-Object { $_.CookedValue } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
        Timestamp = Get-Date
    }
}

# Get baseline metrics (before test)
Write-Host "Getting baseline system metrics..." -ForegroundColor Cyan
$baseline = Get-SystemMetrics

# Start performance monitoring job
Write-Host "Starting performance monitoring..." -ForegroundColor Cyan
$monitorJob = Start-Job -ScriptBlock {
    $metrics = @()
    $endTime = (Get-Date).AddSeconds($using:Duration + 5)

    while ((Get-Date) -lt $endTime) {
        $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
        $memory = Get-Counter '\Memory\% Committed Bytes In Use' -SampleInterval 1 -MaxSamples 1

        $metrics += @{
            Timestamp = Get-Date
            CPU = [math]::Round($cpu.CounterSamples[0].CookedValue, 2)
            Memory = [math]::Round($memory.CounterSamples[0].CookedValue, 2)
        }

        Start-Sleep -Seconds 1
    }

    return $metrics
}

# Start the benchmark
Write-Host "Starting benchmark..." -ForegroundColor Cyan
$benchmarkJob = Start-Job -ScriptBlock {
    param($rate, $duration, $symbols, $multicast, $port)
    cd $using:PWD
    .\market_handler.exe --multicast $multicast --port $port --duration $duration 2>&1
} -ArgumentList $Rate, $Duration, $Symbols, $Multicast, $Port

# Give handler time to start
Start-Sleep -Seconds 2

# Start feed simulator
Write-Host "Starting feed simulator..." -ForegroundColor Cyan
$simulatorJob = Start-Job -ScriptBlock {
    param($rate, $duration, $symbols, $multicast, $port)
    cd $using:PWD
    .\feed_simulator.exe --multicast $multicast --port $port --rate $rate --symbols $symbols --duration $duration 2>&1
} -ArgumentList $Rate, $Duration, $Symbols, $Multicast, $Port

# Wait for benchmark to complete
Write-Host "Running benchmark for $Duration seconds..." -ForegroundColor Cyan
Start-Sleep -Seconds $Duration

# Stop monitoring
Write-Host "Stopping performance monitoring..." -ForegroundColor Cyan
$performanceData = Receive-Job -Job $monitorJob -Wait

# Get final metrics
Write-Host "Getting final system metrics..." -ForegroundColor Cyan
$final = Get-SystemMetrics

# Wait for jobs to complete
$handlerOutput = Receive-Job -Job $benchmarkJob -Wait
$simulatorOutput = Receive-Job -Job $simulatorJob -Wait

# Analyze performance data
$cpuSamples = $performanceData | ForEach-Object { $_.CPU }
$memorySamples = $performanceData | ForEach-Object { $_.Memory }

$avgCPU = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 2)
$maxCPU = [math]::Round(($cpuSamples | Measure-Object -Maximum).Maximum, 2)
$avgMemory = [math]::Round(($memorySamples | Measure-Object -Average).Average, 2)
$maxMemory = [math]::Round(($memorySamples | Measure-Object -Maximum).Maximum, 2)

# Extract throughput and latency from handler output
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

# Generate comprehensive report
Write-Host "Generating performance report..." -ForegroundColor Green

"===============================================" | Out-File -FilePath $resultFile
"COMPREHENSIVE PERFORMANCE MONITORING RESULTS" | Out-File -FilePath $resultFile -Append
"===============================================" | Out-File -FilePath $resultFile -Append
"Test Configuration:" | Out-File -FilePath $resultFile -Append
"  Rate: $Rate msg/sec" | Out-File -FilePath $resultFile -Append
"  Duration: $Duration seconds" | Out-File -FilePath $resultFile -Append
"  Symbols: $Symbols" | Out-File -FilePath $resultFile -Append
"  Timestamp: $timestamp" | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"BASELINE METRICS (before test):" | Out-File -FilePath $resultFile -Append
"  CPU Usage: $($baseline.CPU)%" | Out-File -FilePath $resultFile -Append
"  Memory Usage: $($baseline.Memory)%" | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"PEAK PERFORMANCE METRICS (during test):" | Out-File -FilePath $resultFile -Append
"  Average CPU Usage: $avgCPU%" | Out-File -FilePath $resultFile -Append
"  Peak CPU Usage: $maxCPU%" | Out-File -FilePath $resultFile -Append
"  Average Memory Usage: $avgMemory%" | Out-File -FilePath $resultFile -Append
"  Peak Memory Usage: $maxMemory%" | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"APPLICATION PERFORMANCE:" | Out-File -FilePath $resultFile -Append
"  Throughput: $([math]::Round($throughput, 0)) msg/sec" | Out-File -FilePath $resultFile -Append
"  Throughput Efficiency: $([math]::Round($throughput / $Rate * 100, 1))%" | Out-File -FilePath $resultFile -Append
"  Average Latency: $([math]::Round($avgLatency, 2)) μs" | Out-File -FilePath $resultFile -Append
"  P99 Latency: $([math]::Round($p99Latency, 2)) μs" | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"RESOURCE EFFICIENCY:" | Out-File -FilePath $resultFile -Append
"  CPU per Million msg/sec: $([math]::Round($avgCPU / ($throughput / 1000000), 2))%" | Out-File -FilePath $resultFile -Append
"  Memory Efficiency: $([math]::Round($throughput / $avgMemory, 0)) msg/sec per % memory" | Out-File -FilePath $resultFile -Append
"" | Out-File -FilePath $resultFile -Append

"RAW PERFORMANCE DATA:" | Out-File -FilePath $resultFile -Append
"---------------------" | Out-File -FilePath $resultFile -Append
for ($i = 0; $i -lt $performanceData.Count; $i++) {
    $data = $performanceData[$i]
    "Second $($i + 1): CPU=$($data.CPU)%, Memory=$($data.Memory)%" | Out-File -FilePath $resultFile -Append
}

Write-Host "Performance monitoring completed! Results saved to $resultFile" -ForegroundColor Green

Write-Host "`n=== PERFORMANCE SUMMARY ===" -ForegroundColor Yellow
Write-Host "Throughput: $([math]::Round($throughput, 0)) msg/sec ($([math]::Round($throughput / $Rate * 100, 1))% efficiency)" -ForegroundColor White
Write-Host "Latency: $([math]::Round($avgLatency, 2)) μs avg, $([math]::Round($p99Latency, 2)) μs P99" -ForegroundColor White
Write-Host "CPU Usage: $avgCPU% avg, $maxCPU% peak" -ForegroundColor White
Write-Host "Memory Usage: $avgMemory% avg, $maxMemory% peak" -ForegroundColor White
