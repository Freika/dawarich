import json
import math
import os


NUMBERS = frozenset({
    "good_requests", "offered_rps", "started_iterations", "completed_iterations",
    "dropped_iterations", "errors", "timeouts", "oom_kills", "p50_ms", "p95_ms", "p99_ms",
    "rss_bytes", "working_set_bytes", "memory_current_bytes", "memory_peak_bytes",
    "beam_total_bytes", "cpu_seconds", "generator_cpu_seconds", "duration_seconds",
    "db_cpu_seconds", "repeat", "app_memory_mib", "k6_exit_code",
})
ENUMS = {"app": {"rails", "hybrid", "native"}, "phase": {"warmup", "lower", "higher", "calibration"}}
FLAGS = {"semantic_valid", "oom", "running", "load_pass"}


def project(raw, routes):
    result = {}
    if not isinstance(raw, dict):
        return result
    for key, value in raw.items():
        if key in NUMBERS and type(value) in (int, float) and value >= 0 and math.isfinite(value):
            result[key] = value
        elif key == "route" and isinstance(value, str) and value in routes:
            result[key] = value
        elif key in ENUMS and isinstance(value, str) and value in ENUMS[key]:
            result[key] = value
        elif key in FLAGS and type(value) is bool:
            result[key] = value
        elif key == "samples" and isinstance(value, list):
            result[key] = [project(row, routes) for row in value[:3600] if isinstance(row, dict)]
    return result


def write(path, raw, routes):
    encoded = json.dumps(project(raw, routes), allow_nan=False, sort_keys=True) + "\n"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as output:
        output.write(encoded)
