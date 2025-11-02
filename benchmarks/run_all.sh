#!/usr/bin/env bash

# BakedFileSystem Benchmark Suite
# Runs all benchmarks and generates a comprehensive report

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================================================="
echo "BakedFileSystem Comprehensive Benchmark Suite"
echo "======================================================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print section headers
print_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
    echo ""
}

# Function to print success
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Clean up any existing servers
print_section "Cleanup"
echo "Killing any existing test servers..."
lsof -ti:3000 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti:3001 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 1
print_success "Cleanup complete"

# Create results directory
mkdir -p results

# Run compile time benchmark
print_section "1/4: Compile Time Benchmark"
if crystal run compile_time.cr; then
    print_success "Compile time benchmark complete"
else
    print_error "Compile time benchmark failed"
    exit 1
fi

# Run binary size benchmark
print_section "2/4: Binary Size Analysis"
if crystal run binary_size.cr; then
    print_success "Binary size analysis complete"
else
    print_error "Binary size analysis failed"
    exit 1
fi

# Run memory benchmark
print_section "3/4: Memory Usage Benchmark"
if crystal run memory.cr; then
    print_success "Memory benchmark complete"
else
    print_error "Memory benchmark failed"
    exit 1
fi

# Cleanup between benchmarks
echo "Cleaning up..."
lsof -ti:3000 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti:3001 2>/dev/null | xargs kill -9 2>/dev/null || true
sleep 2

# Run performance benchmark
print_section "4/4: Performance Benchmark"
if crystal run performance.cr; then
    print_success "Performance benchmark complete"
else
    print_error "Performance benchmark failed"
    exit 1
fi

# Final cleanup
echo "Cleaning up..."
lsof -ti:3000 2>/dev/null | xargs kill -9 2>/dev/null || true
lsof -ti:3001 2>/dev/null | xargs kill -9 2>/dev/null || true

# Generate report
print_section "Generating Report"
if crystal run report_generator.cr; then
    print_success "Report generated successfully"
else
    print_error "Report generation failed"
    exit 1
fi

echo ""
echo "======================================================================="
echo -e "${GREEN}All benchmarks completed successfully!${NC}"
echo "======================================================================="
echo ""
echo "Results available in:"
echo "  - results/compile_time.json"
echo "  - results/binary_size.json"
echo "  - results/memory.json"
echo "  - results/performance.json"
echo ""
echo "Comprehensive report:"
echo "  - results/REPORT.md"
echo ""
echo "To view the report:"
echo "  cat results/REPORT.md"
echo ""
