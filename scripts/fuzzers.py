import os
import shutil
import glob
import time
import json

from loguru import logger as log

from scripts.containers import build_image, start_container, stop_container, run_in_container, read_from_stopped_container, remove_container, copy_from_container, get_container_logs

BENCHMARKS_DIR = 'benchmarks'
COMPILER_DIR = 'compiler'


class Fuzzer():
    """
    Base class definition for fuzzers.
    """
    fuzzer_name = None
    fuzzer_context = None

    # Allow reusing the same image across multiple trials
    fuzzer_images = {}
    benchmark_images = {}

    def __init__(self, benchmark_name: str, trial_num: int, compiler_version: str = 'latest', scan_cycle: bool = False, asan_alternate: bool = False):
        """
        Build the image for this fuzzer to run
        """
        assert self.fuzzer_name is not None, 'Fuzzer name must be defined'
        assert self.fuzzer_context is not None, 'Fuzzer context must be defined'

        image_name = f'{self.fuzzer_name}:{benchmark_name}'
        benchmark_image_name = f'plc-compiler-{compiler_version}:{benchmark_name}'

        # Store important vars
        self.image_name = image_name
        self.benchmark_name = benchmark_name
        self.benchmark_image_name = benchmark_image_name
        self.trial_num = trial_num
        self.scan_cycle = scan_cycle
        self.asan_alternate = asan_alternate

        # Check if image already exists
        if image_name in Fuzzer.fuzzer_images:
            log.debug(f'Reusing existing image: {image_name}')
            return

        # Build the benchmark image if not existing
        if benchmark_image_name not in Fuzzer.benchmark_images:
            log.debug(f'Building benchmark image: {image_name}')
            contexts = self.__get_build_contexts(benchmark_name)
            build_image(benchmark_image_name, COMPILER_DIR, additional_contexts=contexts, dockerfile=f'{COMPILER_DIR}/{compiler_version}.Dockerfile')
            Fuzzer.benchmark_images[benchmark_image_name] = True

        # Build the fuzzer image
        build_args = {
            "SCAN_CYCLE": 0 if scan_cycle is False else 1,
            "ASAN_ALT": 0 if asan_alternate is False else 1,
        }
        contexts = self.__get_build_contexts(benchmark_name, compiler_version)
        build_image(image_name, self.fuzzer_context, additional_contexts=contexts, build_args=build_args)
        Fuzzer.fuzzer_images[image_name] = True


    def start_fuzzer(self, caps: list = [], cpuset: str = None, env_vars: dict = {}):
        """
        Start fuzzing container instance
        """
        self.container_id = start_container(
            f'{self.fuzzer_name}:{self.benchmark_name}',
            caps=caps,
            cpuset=cpuset,
            env_vars=env_vars,
        )
        self.fuzzer_start_time = time.time()


    def stop_fuzzer(self):
        """
        Stop fuzzing container instance
        """
        stop_container(self.container_id)
        self.fuzzer_stop_time = time.time()


    def get_fuzzer_elapsed_time(self):
        """
        Returns the elapsed time of the fuzzer
        """
        if self.fuzzer_start_time is None or self.fuzzer_stop_time is None:
            raise ValueError('Fuzzer has not been started or stopped')

        return self.fuzzer_stop_time - self.fuzzer_start_time


    def get_fuzzer_stats(self):
        """
        Returns stats specific for a fuzzer.
        """
        pass


    def cleanup(self):
        """
        Ensure the container is stopped when the object is deleted
        """
        if hasattr(self, 'container_id'):
            log.debug(f'Removing container {self.container_id} ({self.fuzzer_name})')
            remove_container(self.container_id)

    @classmethod
    def __get_build_contexts(cls, benchmark_name, compiler_version = None):
        """
        Returns a Docker build context for a given benchmark.
        """
        contexts = {
            'fuzztarget': os.path.join(BENCHMARKS_DIR, benchmark_name),
        }

        # Also include benchmark image when specified
        if compiler_version:
            contexts["icsbuild"] = f"docker-image://plc-compiler-{compiler_version}:{benchmark_name}"
        
        return contexts


class ICSQuartz(Fuzzer):
    """
    ICSQuartz class definition
    """
    fuzzer_name = 'icsquartz'
    fuzzer_context = 'icsquartz'
    fuzzer_caps = ['SYS_NICE']
    compiler_images = None


    def start_fuzzer(self, cpus: list, cpuset=None):
        """
        Start fuzzing container instance
        """

        # Standard ASAN benchmarks (work well on most benchmarks)
        asan_options = {
            'halt_on_error': 1,
            'abort_on_error': 1,
            'exitcode': 0,
            'detect_leaks': 0,
            'malloc_context_size': 0,
            'symbolize': 0,
            'allocator_may_return_null': 1,
            'detect_odr_violation': 0,
            'handle_segv': 0,
            'handle_sigbus': 1,
            'handle_abort': 0,
            'handle_sigfpe': 0,
            'handle_sigill': 1,
            'print_summary': 0,
            'print_legend': 0,
            'print_full_thread_history': 0,
            'symbolize_inline_frames': 0,
        }

        # Some benchmarks perform better with these configurations
        if self.asan_alternate:
            asan_options['halt_on_error'] = 0
            asan_options['abort_on_error'] = 0
            asan_options['handle_sigbus'] = 0
            asan_options['handle_sigill'] = 0
            asan_options['log_path'] = './asanlog'

        env_vars = {
            'SEED': str(self.trial_num),
            'CORES': ",".join([str(i) for i in cpus]),
            'SCAN_CYCLE_MAX': 2 if self.scan_cycle is False else 10_000,
            'SCAN_CYCLE_ARGS': '' if self.scan_cycle is False else '--state-resets --dynamic-scan-cycle',
            'MUTATOR_POWER': 4,
            'FUZZER_LOG': 'fuzzer_log',
            # 'RUST_BACKTRACE': 1,
            'ASAN_OPTIONS': ':'.join([f'{key}={value}' for key,value in asan_options.items() ])
        }

        super().start_fuzzer(caps=ICSQuartz.fuzzer_caps, env_vars=env_vars, cpuset=cpuset)

    def get_fuzzer_logs(self):
        """
        Returns the logs of the fuzzer
        """
        log_dir = '.icsquartz-logs'
        prefix = f"{self.fuzzer_name}.{self.benchmark_name}.{self.trial_num}"
        os.makedirs(os.path.join(log_dir, prefix), exist_ok=True)

        program_log_path = os.path.join(log_dir, prefix, 'program.log')
        fuzzer_log_path = os.path.join(log_dir, prefix, 'fuzzer.log')

        # Remove existing logfiles
        try:
            os.remove(program_log_path)
        except FileNotFoundError:
            pass
        try:
            os.remove(fuzzer_log_path)
        except FileNotFoundError:
            pass

        # Copy program out
        try:
            copy_from_container(self.container_id, '/out/fuzzer_log', program_log_path)
        except Exception as e:
            log.error(f"Unable to fetch fuzzer_log from container ({self.container_id})")
            pass

        # Copy docker out
        fuzzer_logs = get_container_logs(self.container_id)
        with open(fuzzer_log_path, 'w+') as f:
            f.write(fuzzer_logs)


    def get_fuzzer_stats(self):
        """
        Returns execution metrics for fuzzer.
        """

        results_tempdir = '.icsquartz-results'

        # Remove the last used tempdir
        try:
            shutil.rmtree(results_tempdir)
        except FileNotFoundError:
            pass

        # Create a tempdir to store
        os.makedirs(results_tempdir, exist_ok=True)

        # Pull info from fuzzer
        try:
            copy_from_container(self.container_id, '/out/fuzzer_stats.json', results_tempdir)
            copy_from_container(self.container_id, '/out/crashes/', results_tempdir)
            copy_from_container(self.container_id, '/out/corpus/', results_tempdir)
        except Exception as e:
            log.error(f"Unable to copy files out from fuzzer: {e}")
            return { 'execs_per_sec': 0, 'execs_total': 0, 'first_crash_time': None, 'first_crash_executions': None }

        # Parse the last line
        results_tempdir = '.icsquartz-results'
        with open(os.path.join(results_tempdir, 'fuzzer_stats.json'), 'r') as f:
            # Store atleast 2 lines back (sometimes the most recent hasn't finished writing)
            last_last_line = ""
            last_line = ""
            while (line := f.readline()):
                last_last_line = last_line
                last_line = line

        # Load into json
        try:
            stats = json.loads(last_line)
        except json.JSONDecodeError:
            stats = json.loads(last_last_line)
        log.debug(f'Loaded stats: {stats}')

        # Executions / sec
        execs_per_sec = stats["exec_sec"]
        execs_total = stats["executions"]

        state_resets = 0
        try:
            # execs_total_alt is useful when using multi-core fuzzing.
            # execs_total_alt = stats['client_stats'][1]['user_monitor']['executions_']['value']['Number']
            state_resets = stats['client_stats'][1]['user_monitor']['stale_state_']['value']['Number']
        except KeyError:
            pass

        # Parse all crashes
        crash_stats = []
        crashes = glob.glob(os.path.join(results_tempdir, 'crashes/.*.metadata'))
        for crash in crashes:
            with open(crash, 'r') as f:
                stats = json.loads(f.read())

            exec_time_secs = stats["exec_time"]["secs"]
            exec_times_nsecs = stats["exec_time"]["nanos"]
            exec_time = exec_time_secs + (exec_times_nsecs / 1e9)
            executions = stats["executions"]

            crash_stats.append({
                "exec_time": exec_time,
                "executions": executions
            })

        # Sort by executions (asc)
        crash_stats.sort(key=lambda x: x["executions"])

        # Extract first crash
        first_crash_time = None
        first_crash_executions = None
        if len(crash_stats) > 0:
            first_crash_time = crash_stats[0]["exec_time"]
            first_crash_executions = crash_stats[0]["executions"]

        return {
            'execs_per_sec': execs_per_sec,
            'execs_total': execs_total,
            'first_crash_time': first_crash_time,
            'first_crash_executions': first_crash_executions,
            'state_rests': state_resets if self.scan_cycle is True else 0,
        }
