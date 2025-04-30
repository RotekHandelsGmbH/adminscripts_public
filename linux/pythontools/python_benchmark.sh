#!/bin/bash

# Use your specified Python binary
PYTHON_BINARY=/opt/python-latest/bin/python3
RESULTS_DIR=./bench_results
BASELINE_JSON=$RESULTS_DIR/baseline.json
RUN_ID=$(date +"%Y%m%d_%H%M%S")
OUTPUT_JSON=$RESULTS_DIR/run_$RUN_ID.json

rm -rf ./dask-worker-space
rm -rf ./venv

mkdir -p "$RESULTS_DIR"

echo "Installing pyperformance..."
$PYTHON_BINARY -m pip install --upgrade pyperformance > /dev/null

echo "Running pyperformance benchmark..."
$PYTHON_BINARY -m pyperformance run --python=$PYTHON_BINARY --output=$OUTPUT_JSON

echo "✅ Benchmark complete. Results saved to: $OUTPUT_JSON"

if [ -f "$BASELINE_JSON" ]; then
    echo "Comparing against baseline..."
    $PYTHON_BINARY -m pyperformance compare $BASELINE_JSON $OUTPUT_JSON
else
    echo "No baseline found. To set one:"
    echo "  cp $OUTPUT_JSON $BASELINE_JSON"
fi

rm -rf ./dask-worker-space
rm -rf ./venv
