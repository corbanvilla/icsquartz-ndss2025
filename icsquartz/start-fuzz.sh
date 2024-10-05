#!/bin/bash

set -ex

# Start fuzzer
$OUT/$FUZZ_TARGET \
    --seed $SEED \
    --cores $CORES \
    --mutator-pow $MUTATOR_POWER \
    --fuzzer-log $FUZZER_LOG \
    --scan-cycle-max $SCAN_CYCLE_MAX \
    $SCAN_CYCLE_ARGS
