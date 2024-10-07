#!/usr/bin/env python3

import os
import time
import math
import argparse
from pprint import pprint
from itertools import islice

import pandas as pd
from loguru import logger as log

from scripts.experiments import table_3, table_4, table_5, cve
from scripts.fuzzers import ICSQuartz

results_dir = 'results'

def fuzz_targets(benchmarks: list, compiler: str, scan_cycle: bool, asan_alternate: bool, build_only: bool, fuzz_trials: int, fuzz_time: int, fuzzers: list):
    all_stats = []
    fuzzer_instances = []

    # 1 - Build all fuzzer images
    for benchmark in benchmarks:
        for Fuzzer in fuzzers:
            log.info(f"Creating {Fuzzer.fuzzer_name} experiments (n={fuzz_trials})...")
            for trial in range(fuzz_trials):
                fuzzer_instances.append(Fuzzer(benchmark, trial, compiler, scan_cycle, asan_alternate))

    log.info(f"Loaded {len(fuzzer_instances)} fuzzer trials!")
    log.info(f"This will take approximately {math.ceil(len(fuzzer_instances) / concurrent_fuzzers) * fuzz_time} seconds to complete.")

    # Dry-run mode
    if build_only:
        log.info("Build-only mode enabled... Quitting!")
        return

    # Loop through experiments in batches
    batch_iter = iter(fuzzer_instances)
    experiment_count = 0
    while (batch := list(islice(batch_iter, concurrent_fuzzers))):
        log.info(f"Starting batch of {len(batch)} fuzzers... ({experiment_count}/{len(fuzzer_instances)})")
        log.info(f"Allowing fuzzing for {fuzz_time} seconds")
        experiment_count += len(batch)

        # 2 - Start all fuzzers
        start_fuzz_time = time.time()
        for cpu_idx, fuzzer_instance in enumerate(batch):
            log.info(f"Starting {fuzzer_instance.fuzzer_name} fuzzer")
            fuzzer_instance.start_fuzzer(cpus=[cpus[cpu_idx]], cpuset=cpuset)

        # 3 - Allow fuzzing to run (subtracting time it took to launch all containers)
        sleep_time = fuzz_time - (time.time() - start_fuzz_time)
        log.info(f"All containers started! Sleeping for {sleep_time} more seconds to finish fuzzing.")
        if sleep_time > 0:
            time.sleep(sleep_time)

        # 4 - Stop all fuzzers
        for fuzzer in batch:
            fuzzer.stop_fuzzer()
            log.info(f"Fuzzer elapsed time: {fuzzer.get_fuzzer_elapsed_time()}")

    # 5 - Collect stats from each fuzzer
    for fuzzer in fuzzer_instances:
        # Store logs
        # fuzzer.get_fuzzer_logs()

        # Store stats
        stats = fuzzer.get_fuzzer_stats()
        stats["benchmark"] = fuzzer.benchmark_name
        stats["fuzzer"] = fuzzer.fuzzer_name
        stats["trial"] = fuzzer.trial_num
        stats["elapsed_time"] = fuzzer.get_fuzzer_elapsed_time()

        all_stats.append(stats)

    # 6 - Remove all containers
    for fuzzer in fuzzer_instances:
        fuzzer.cleanup()

    # 7 - Statistical Analysis
    results_timestamp = int(time.time())
    os.makedirs(results_dir, exist_ok=True)

    # 8 - CSV Stats
    df = pd.DataFrame(all_stats)

    # Data Cleanup
    columns = df.columns.tolist()
    columns.remove('fuzzer')
    columns.remove('benchmark')
    new_order = ['fuzzer', 'benchmark'] + columns
    df = df[new_order]

    # All stats
    df.to_csv(os.path.join(results_dir, f'{results_timestamp}-all.csv'), index=False)
    df.to_csv(os.path.join(results_dir, f'latest-all.csv'), index=False)

    # Averaged metrics (per benchmark)
    grouped = df.drop(columns=['trial']).groupby(['fuzzer', 'benchmark'])
    mean_stats = grouped.mean().reset_index()
    mean_stats['elapsed_time_std_dev'] = grouped['elapsed_time'].std().reset_index()['elapsed_time']
    mean_stats.to_csv(os.path.join(results_dir, f'{results_timestamp}-per-benchmark.csv'), index=False)
    mean_stats.to_csv(os.path.join(results_dir, f'latest-per-benchmark.csv'), index=False)

    # Averaged metrics (overall)
    grouped = df.drop(columns=['benchmark', 'trial']).groupby(['fuzzer'])
    mean_stats_overall = grouped.mean().reset_index()
    mean_stats_overall['elapsed_time_std_dev'] = grouped['elapsed_time'].std().reset_index()['elapsed_time']
    mean_stats_overall.to_csv(os.path.join(results_dir, f'{results_timestamp}-overall.csv'), index=False)
    mean_stats_overall.to_csv(os.path.join(results_dir, f'latest-overall.csv'), index=False)



if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Run fuzzing experiment.")
    parser.add_argument('--fuzz-time', type=int, default=30, help='Time for fuzzing in seconds')
    parser.add_argument('--fuzz-trials', type=int, default=3, help='Number of fuzzing trials (per benchmark)')
    parser.add_argument('--cpus', type=str, default='1-59', help='Range of CPUs to use at once (e.g., 1-59).')
    parser.add_argument('--experiment', type=str, choices=['table_3', 'table_4', 'table_5', 'cve', 'build-all'], required=True, help='The experiment set to run.')
    parser.add_argument('--cpus-isolated', action='store_true', help='Whether these CPUs have been isolated by the kernel scheduler.')
    parser.add_argument('--build-only', action='store_true', help='Build images but do not fuzz.')
    args = parser.parse_args()

    # Parse cpu range into list
    cpuset = args.cpus if args.cpus_isolated else None
    cpus = []
    if args.cpus:
        for part in args.cpus.split(','):
            if '-' in part:
                a, b = part.split('-')
                cpus.extend(range(int(a), int(b) + 1))
            else:
                cpus.append(int(part))
    concurrent_fuzzers = len(cpus)

    # Select the benchmark and compiler to use
    benchmark_configs = []
    build_only = args.build_only
    match args.experiment:
        case 'table_3':
            benchmark_configs.append(table_3)
        case 'table_4':
            benchmark_configs.append(table_4)
        case 'table_5':
            benchmark_configs.append(table_5)
        case 'cve':
            benchmark_configs.append(cve)
        case 'build-all':
            build_only = True
            benchmark_configs.extend([table_3, table_4, table_5, cve])

    # Run benchmark configs
    fuzzers = [ICSQuartz]
    for config in benchmark_configs:
        compiler = config["compiler"]
        benchmarks = config["benchmarks"]
        scan_cycle = config["scan_cycle"]
        asan_alternate = config["asan_alternate"]
        results = config["results"]
        results_columns = config["results_columns"]

        # Fuzz
        fuzz_targets(benchmarks, compiler, scan_cycle, asan_alternate, build_only, args.fuzz_trials, args.fuzz_time, fuzzers)

        # Print key results
        if not build_only:
            for result in results:
                df = pd.read_csv(os.path.join(results_dir, result))
                columns = []
                if 'fuzzer' in df.columns:
                    columns.append('fuzzer')
                if 'benchmark' in df.columns:
                    columns.append('benchmark')
                columns += results_columns

                print(f'--------- {result} ---------')
                print(df[columns].to_string(index=False))
