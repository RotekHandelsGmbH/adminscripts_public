#!/bin/bash

# Paths (adjust as needed)
PYTHON_BINARY=/opt/python-latest/bin/python3
RESULTS_DIR=./bench_results
BASELINE_JSON=$RESULTS_DIR/baseline.json
RUN_ID=$(date +"%Y%m%d_%H%M%S")
TMP_RUN_DIR=$RESULTS_DIR/tmp_$RUN_ID
AVERAGED_JSON=$RESULTS_DIR/avg_$RUN_ID.json

mkdir -p "$TMP_RUN_DIR"

echo "Installing pyperformance..."
$PYTHON_BINARY -m pip install --upgrade pyperformance > /dev/null

echo "Running pyperformance 5 times..."
for i in {1..5}; do
    OUT_FILE=$TMP_RUN_DIR/run_$i.json
    echo "  Run #$i..."
    $PYTHON_BINARY -m pyperformance run --quiet --python=$PYTHON_BINARY --output=$OUT_FILE
done

echo "Merging runs into average result..."
$PYTHON_BINARY -m pyperformance merge $TMP_RUN_DIR/*.json --output $AVERAGED_JSON

echo "Saved averaged results to: $AVERAGED_JSON"

if [ -f "$BASELINE_JSON" ]; then
    echo "Comparing against baseline..."
    $PYTHON_BINARY -m pyperformance compare $BASELINE_JSON $AVERAGED_JSON
else
    echo "No baseline found. To set one:"
    echo "  cp $AVERAGED_JSON $BASELINE_JSON"
fi
