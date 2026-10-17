import hashlib
import json
import re


HASH_FIELDS = {"runtime_tree_sha256", "schema_sha256", "dataset_sha256", "workload_sha256"}
CONTROLS = {
    "app_cpus": {2}, "app_memory_mib": {512, 1024}, "swap_mib": {0}, "pool": {10},
    "db_cpus": {2}, "db_memory_mib": {1024}, "redis_memory_mib": {128},
    "jobs": {"idle"}, "schedulers": {2}, "puma_workers": {2}, "puma_threads": {5}, "yjit": {True},
}
RUNTIMES = {"ruby-3.4.9-yjit", "elixir-1.20.4-otp-27"}


def digest(raw):
    return hashlib.sha256(json.dumps(raw, sort_keys=True, separators=(",", ":"),
                                    allow_nan=False).encode()).hexdigest()


def seal(raw):
    required = HASH_FIELDS | {"source_sha", "image_id", "runtime", "config"}
    if set(raw) != required:
        raise ValueError("invalid provenance fields")
    for key in HASH_FIELDS | {"source_sha", "image_id"}:
        pattern = r"[a-f0-9]{40}" if key == "source_sha" else r"[a-f0-9]{64}"
        if key == "image_id":
            pattern = "sha256:" + pattern
        if not isinstance(raw[key], str) or re.fullmatch(pattern, raw[key]) is None:
            raise ValueError("invalid provenance identity")
    if raw["runtime"] not in RUNTIMES:
        raise ValueError("runtime must match approved controls")
    config = raw["config"]
    if not isinstance(config, dict) or set(config) != set(CONTROLS):
        raise ValueError("invalid control fields")
    for key, allowed in CONTROLS.items():
        value = config[key]
        expected = bool if key == "yjit" else str if key == "jobs" else int
        if type(value) is not expected or value not in allowed:
            raise ValueError("unapproved runtime control")
    result = {**raw, "config": dict(config), "version": 1}
    result["identity_sha256"] = digest(result)
    return result


def matched_controls(left, right):
    left, right = seal(left), seal(right)
    return all(left[key] == right[key] for key in
               ("schema_sha256", "dataset_sha256", "workload_sha256", "config"))
