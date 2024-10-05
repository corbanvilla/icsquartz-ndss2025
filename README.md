# ICS-QUARTZ Artifact Evaluation

## Prerequisites

### Dependencies

1. A Linux System (validated on Ubuntu 22.04).
2. [Docker](https://docs.docker.com/engine/install/ubuntu/) (validated with 27.3.1).
3. [Python](https://github.com/pyenv/pyenv) (**requires** 3.10 or higher).
4. `git`, `pip`, `venv` (`sudo apt install -y git python3-pip python3-venv`).

### System Configuration

The experiment script (`run_experiment.py`) expects your user to have permission to execute `docker` commands without `sudo`. You can do this by adding your user to the `docker` group (i.e. `sudo usermod -aG docker $USER` and logout then login).
> 
> If a `docker` group does not exist, you may need to [add it manually](https://docs.docker.com/engine/install/linux-postinstall/) (i.e. `sudo groupadd docker`).
> 

### ICS-QUARTZ

First you will want to download the ICS-QUARTZ repository to run the experiments. Install the requires Python packages as well:
```bash
git clone https://github.com/corbanvilla/icsquartz-ndss2025.git icsquartz
cd ./icsquartz
python3 -m venv ./venv # Creates a virtual environment
source ./venv/bin/activate # Activates the virtual Python environment
pip install -r requirements.txt
```

## Experiments

### Reproducing Results (Tables III, IV, V)
To reproduce the results shown in Tables III, IV, and V, we include a script (`run_experiment.py`) in the main folder, which manages the benchmark build process and fuzzing campaign across multiple processors. The script allows you to adjust the following experiment parameters:

- Fuzz time: The time (in seconds) to fuzz each program binary.
- Fuzz trials: The number of times to repeat each fuzzing experiment to demonstrate statistical significance.
- CPUs: The specific cores available to allocate for fuzzing (e.g., `1-8`). One experiment will be allocated per core.
- Experiment: The specific experiment to reproduce (e.g., `table_3`, `table_4`, `table_5`, `cve`).

Configurations are passed to the script as command-line parameters:

```bash
./run_experiment.py --fuzz-time 180 --fuzz-trials 3 --cpus 1-8 --experiment table_3
```

Invoking the experiment script will automatically:

1. Build the ST compiler (defined in `compiler/`) and compile the program source into an instrumented binary.
2. Build fuzzing targets required for the experiment (defined in `scripts/experiment.py`) using the ICS-QUARTZ fuzzer (`icsquartz/Dockerfile`).
3. Create a queue of size: `fuzz_time × fuzz_trials × |benchmarks|`.
4. Execute jobs from the queue in batches of size: `cpus`.
5. Collect and aggregate statistics into `results/`.
6. The time required for the build stages will vary, and may take significantly longer for the first experiment as dependencies are downloaded and built in the containers.
​
### Experiment (E1)
**[Performance] | [Table III] | [10 human-minutes + 1.5 compute-hour]**

In this experiment, we reproduce the comparison with state-of-the-art fuzzers. The following parameters should require approximately 1 hour to fuzz all 17 benchmarks, though we encourage the evaluator to increase `fuzz_time` or `cpus` if more time and resources are available.

```bash
./run_experiment.py --fuzz-time 565 --fuzz-trials 3 --cpus 1-8 --experiment table_3
```
**Results:**
Key results of the fuzzing can be found under `results/`, where `latest-per-benchmark.csv` includes statistics averaged across each of the 3 trials, and `latest-overall.csv` aggregates averages over all experiments conducted. The key metrics to compare in this experiment are `execs_per_sec` and `first_crash_executions` (Table III). While we expect executions per second to vary significantly depending on the hardware, the inputs to first crash should not.

### Experiment (E2)
**[Fuzzing Campaign] | [Table IV] | [10 human-minutes + 1.5 compute-hour]**

In this experiment, we reproduce the fuzzing campaign across the OSCAT Basic library using a subset of 18 benchmarks which result in crashes.

```bash
./run_experiment.py --fuzz-time 533 --fuzz-trials 3 --cpus 1-8 --experiment table_4
```

**Results:**
Key results of the fuzzing can be found under `results/`, where `latest-all.csv` should include crashes (`first_crash_time` and `first_crash_executions`) for all programs evaluated. It should be noted that Table III will change as part of the major revision to include a comparison with FieldFuzz and ICSFuzz.

### Experiment (E3)
**[CVE] | [10 human-minutes + 0.2 compute-hour]**

In this experiment, we reproduce the OSCAT Basic CVE.

```bash
./run_experiment.py --fuzz-time 500 --fuzz-trials 3 --cpus 1-8 --experiment cve
```

**Results:**
The resulting CVE crash can be located under `results/`, where `latest-all.csv` should include a crash for the benchmark.

### Experiment (E4)
**[Scan Cycle Fuzzing] | [Table IV] | [10 human-minutes + 0.2 compute-hour]**

In this experiment, we reproduce the ICS-QUARTZ scan cycle fuzzing campaign on 6 benchmarks.

```bash
./run_experiment.py --fuzz-time 500 --fuzz-trials 3 --cpus 1-8 --experiment table_5
```

**Results:**
The key results can be found under `results/`, where the `state_resets` metric indicates the number of times the scan cycle mutation algorithm intervened to reset stale execution paths. The higher number of `first_crash_executions` in these benchmarks reflects the stateful complexity introduced by ST programs tracking residual states.

