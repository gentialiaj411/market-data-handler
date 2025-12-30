#include "../src/message_parser.h"
#include "../src/order_book.h"
#include "../src/utils/stats.h"
#include "../src/utils/timestamp.h"

#include <chrono>
#include <iostream>

namespace {

void run_latency_benchmark() {
    const size_t iterations = 2'000'000;
    market::MessageParser parser;
    market::OrderBook book;
    market::LatencyStats stats;

    market::RawMessage raw{};
    raw.len = sizeof(market::Quote);

    auto* quote = reinterpret_cast<market::Quote*>(raw.payload.data());
    quote->header.msg_type = market::MSG_QUOTE;
    quote->header.msg_len = static_cast<uint16_t>(sizeof(market::Quote));
    quote->bid_price = 1'500'000;
    quote->ask_price = quote->bid_price + 50;
    quote->bid_size = 100;
    quote->ask_size = 100;
    quote->symbol_id = 1001;

    const auto start_all = market::now_ns();
    for (size_t i = 0; i < iterations; ++i) {
        quote->header.sequence_num = static_cast<uint32_t>(i + 1);
        quote->header.timestamp_ns = market::now_ns();
        raw.recv_timestamp_ns = market::now_ns();
        const market::MessageHeader* header = parser.parse(raw);
        if (header) {
            book.on_quote(*parser.as<market::Quote>(header));
        }
        stats.record(market::now_ns() - raw.recv_timestamp_ns);
    }
    const auto end_all = market::now_ns();

    const double seconds = static_cast<double>(end_all - start_all) / 1e9;
    const double throughput = iterations / seconds;

    std::cout << "Latency benchmark\n";
    std::cout << "  Iterations: " << iterations << "\n";
    std::cout << "  Throughput: " << throughput << " msg/s\n";
    std::cout << "  Duration:   " << seconds << " sec\n";
    const auto snap = stats.snapshot();
    std::cout << "  Avg latency: " << snap.avg_ns << " ns\n";
    std::cout << "  P95:         " << snap.p95_ns << " ns\n";
    std::cout << "  P99:         " << snap.p99_ns << " ns\n";
}

}

int main() {
    run_latency_benchmark();
    return 0;
}
