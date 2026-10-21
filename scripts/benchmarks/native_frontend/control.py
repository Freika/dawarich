import re

from ownership import Docker, HARNESS, HARNESS_KEY, OWNER_KEY, docker_command


ROLES = {"rails", "hybrid", "db", "redis", "client", "network"}
CASES = {"map", "stats_page", "trips", "imports", "points_page", "points_api",
         "tracks_api", "stats_api", "visits_api", "points_tile"}
FIXED = {"version": 1, "warmup_seconds": 30, "trial_seconds": 60, "grace_seconds": 10,
         "repetitions": 3, "preallocated_vus": 32, "max_vus": 32,
         "app_memory_mib": [512, 1024], "idle_socket_cohorts": [1, 10, 50],
         "slo": "calibrate-then-controller-approve"}
COUNTS = {"points": 100000, "tracks": 40, "visits": 40, "trips": 20, "imports": 20, "stats": 1}
API_RATES = {"points_api": [50, 300], "tracks_api": [5, 100], "stats_api": [20, 200],
             "visits_api": [20, 200], "points_tile": [2, 8]}


def validate_manifest(manifest):
    if set(manifest) != set(FIXED) | {"fixture_counts", "cases"}:
        raise ValueError("invalid workload fields")
    if any(type(manifest[k]) is not type(v) or manifest[k] != v for k, v in FIXED.items()):
        raise ValueError("controller approval required for budget changes")
    if manifest["fixture_counts"] != COUNTS:
        raise ValueError("unmatched fixture counts")
    cases = manifest["cases"]
    if len(cases) != 10 or {c["id"] for c in cases} != CASES:
        raise ValueError("ten distinct routes required")
    for case in cases:
        if case["rates"] != API_RATES.get(case["id"], [10, 100]):
            raise ValueError("unapproved arrival profile")


def resources(names):
    if set(names) != ROLES:
        raise ValueError("supplied resource names required")
    return {"container": [names[r] for r in ("rails", "hybrid", "db", "redis", "client")],
            "network": [names["network"]]}


def limits(cpu, memory):
    return ["--cpus", str(cpu), "--memory", f"{memory}m", "--memory-swap", f"{memory}m"]


def plan(run_id, names, images, contexts, env_files, manifest):
    validate_manifest(manifest)
    Docker(run_id, resources(names), None)
    if set(images) != ROLES - {"network"} or any(
            not re.fullmatch(r"sha256:[a-f0-9]{64}", i) for i in images.values()):
        raise ValueError("pinned local image identities required")
    if set(contexts) != {"rails", "hybrid"} or set(env_files) != {"rails", "hybrid", "db"}:
        raise ValueError("private build inputs and env files required")
    labels = ["--label", OWNER_KEY + "=" + run_id, "--label", HARNESS_KEY + "=" + HARNESS]
    common = labels + ["--network", names["network"]]
    commands = [docker_command("network", "create", "--internal", *labels, names["network"])]
    for role, cpu, memory, tail in (
        ("db", 2, 1024, []),
        ("redis", 0.5, 128, ["redis-server", "--save", "", "--appendonly", "no"]),
        ("client", 2, 512, ["sleep", "infinity"]),
        ("rails", 2, 512, ["puma", "-C", "config/puma.rb"]),
        ("hybrid", 2, 512, ["start"]),
    ):
        args = ["container", "create", "--name", names[role], *common, *limits(cpu, memory)]
        if role in env_files:
            args += ["--env-file", env_files[role]]
        if role == "hybrid":
            args += ["--entrypoint", "/opt/dawarich/bin/dawarich"]
        if role == "client":
            args += ["--entrypoint", "sleep"]
            tail = ["infinity"]
        commands.append(docker_command(*args, images[role], *tail))
    build_commands = []
    for role, target in (("rails", "coexistence_runtime"), ("hybrid", "native_runtime")):
        args = ["build", *labels, "--target", target, "--file", contexts[role] + "/docker/Dockerfile"]
        if role == "hybrid":
            args += ["--build-arg", "ELIXIR_VERSION=1.20.4"]
        args += ["--tag", names[role] + ":control", contexts[role]]
        build_commands.append(docker_command(*args))
    schedule = []
    for cap in manifest["app_memory_mib"]:
        for repeat in range(1, manifest["repetitions"] + 1):
            order = ["rails", "hybrid"] if repeat % 2 else ["hybrid", "rails"]
            cases = manifest["cases"] if repeat % 2 else list(reversed(manifest["cases"]))
            for case in cases:
                for app in order:
                    schedule.append({"app": app, "route": case["id"], "repeat": repeat,
                                     "app_memory_mib": cap, "warmup_seconds": 30,
                                     "lower_rps": case["rates"][0], "higher_rps": case["rates"][1],
                                     "trial_seconds": 60, "grace_seconds": 10})
    return {"mode": "dry-run", "commands": commands, "build_commands": build_commands,
            "schedule": schedule, "measured_trials": len(schedule) * 2,
            "minimum_seconds": len(schedule) * (30 + 2 * (60 + 10))}
