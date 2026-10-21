import copy
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import artifacts
import control
import ownership
import provenance


class FakeDocker:
    def __init__(self, records):
        self.records = records
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append(command)
        if "inspect" in command:
            record = self.records.get(command[-1])
            return SimpleNamespace(returncode=0 if record else 1,
                                   stdout=json.dumps(record) if record else "",
                                   stderr="No such resource" if not record else "")
        return SimpleNamespace(returncode=0, stdout="", stderr="")


def identity():
    return {
        "source_sha": "a" * 40, "runtime_tree_sha256": "b" * 64,
        "image_id": "sha256:" + "c" * 64, "runtime": "elixir-1.20.4-otp-27",
        "schema_sha256": "d" * 64, "dataset_sha256": "e" * 64,
        "workload_sha256": "f" * 64,
        "config": {"app_cpus": 2, "app_memory_mib": 512, "swap_mib": 0,
                   "pool": 10, "db_cpus": 2, "db_memory_mib": 1024,
                   "redis_memory_mib": 128, "jobs": "idle", "schedulers": 2,
                   "puma_workers": 2, "puma_threads": 5, "yjit": True},
    }


def manifest():
    return json.loads((ROOT / "workload.json").read_text())


class HarnessTest(unittest.TestCase):
    def test_cleanup_refuses_resources_without_its_run_ownership_label(self):
        """benchmark cleanup refuses resources without its run ownership label"""
        names = {"container": ["probe-app", "probe-db"], "network": ["probe-net"]}
        labels = {ownership.OWNER_KEY: "probe", ownership.HARNESS_KEY: ownership.HARNESS}
        records = {name: {"Id": name + "-immutable", "Labels": labels, "Running": False}
                   for group in names.values() for name in group}
        for name in records:
            for bad in ({}, {**labels, ownership.OWNER_KEY: "another"},
                        {**labels, ownership.HARNESS_KEY: "another"}):
                fake = FakeDocker({**records, name: {"Id": "foreign", "Labels": bad, "Running": False}})
                with self.assertRaises(ownership.Refusal):
                    ownership.Docker("probe", names, fake).cleanup()
                self.assertTrue(all("inspect" in c for c in fake.calls))
        fake = FakeDocker(records)
        commands = ownership.Docker("probe", names, fake).cleanup()
        self.assertEqual(len(commands), 3)
        self.assertEqual(commands[-1][-3:], ["network", "rm", "probe-net-immutable"])
        self.assertTrue(all(c[:3] == ["docker", "--context", "orbstack"] for c in fake.calls))
        self.assertTrue(all(c[-1].endswith("-immutable") for c in commands))
        self.assertFalse(any("-f" in c or "-v" in c for c in commands))
        fake = FakeDocker({**records, "probe-app": {"Id": "running", "Labels": labels, "Running": True}})
        with self.assertRaises(ownership.Refusal):
            ownership.Docker("probe", names, fake).cleanup()
        self.assertTrue(all("inspect" in c for c in fake.calls))
        self.assertEqual(ownership.Docker("probe", names, FakeDocker({})).cleanup(), [])

    def test_setup_refuses_existing_names_and_unknown_inspection_errors(self):
        """benchmark setup refuses existing names and uncertain Docker state"""
        names = {"container": ["probe-app"], "network": ["probe-net"]}
        for labels in ({}, {ownership.OWNER_KEY: "probe"}):
            fake = FakeDocker({"probe-net": {"Id": "existing", "Labels": labels}})
            with self.assertRaises(ownership.Refusal):
                ownership.Docker("probe", names, fake).require_absent()
        def unavailable(command, **kwargs):
            return SimpleNamespace(returncode=1, stdout="", stderr="daemon unavailable")
        with self.assertRaises(ownership.Refusal):
            ownership.Docker("probe", names, unavailable).require_absent()
        for bad in ("", "bad;command", "--option"):
            with self.assertRaises(ownership.Refusal):
                ownership.Docker(bad, names, FakeDocker({}))
        ownership.Docker("probe", names, FakeDocker({})).require_absent()

    def test_artifacts_redact_credential_and_signed_session_material(self):
        """benchmark artifacts redact credential and signed session material"""
        sentinel = "SYNTHETIC_PRIVATE_MATERIAL"
        raw = {"route": "map", "good_requests": 12, "p95_ms": 1.5,
               "dropped_iterations": 7, "oom_kills": 1, "errors": 2,
               "cookie": sentinel, "query": "?token=" + sentinel,
               "exception": RuntimeError(sentinel), "session": sentinel,
               "authorization": sentinel, "repo": {"password": sentinel},
               "samples": [{"rss_bytes": 123, "raw": sentinel}],
               "route_url": "https://example.invalid/?csrf=" + sentinel}
        result = artifacts.project(raw, {"map"})
        encoded = json.dumps(result)
        self.assertNotIn(sentinel, encoded)
        self.assertEqual(result, {"route": "map", "good_requests": 12, "p95_ms": 1.5,
                                 "dropped_iterations": 7, "oom_kills": 1, "errors": 2,
                                 "samples": [{"rss_bytes": 123}]})
        for key in ("route", "p95_ms", "good_requests"):
            self.assertNotIn(sentinel, json.dumps(artifacts.project({key: sentinel}, {"map"})))
        self.assertEqual(artifacts.project({"p95_ms": float("nan"), "rss_bytes": -1,
                                            "errors": True}, {"map"}), {})
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "result.json"
            artifacts.write(path, raw, {"map"})
            self.assertNotIn(sentinel, path.read_text())
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                artifacts.write(path, raw, {"map"})
            link = pathlib.Path(directory) / "link.json"
            link.symlink_to(path)
            with self.assertRaises(OSError):
                artifacts.write(link, raw, {"map"})

    def test_provenance_invalidates_changed_source_runtime_fixture_and_controls(self):
        """benchmark provenance invalidates changed source runtime fixture and controls"""
        baseline = provenance.seal(identity())
        self.assertEqual(len(baseline["identity_sha256"]), 64)
        for field in ("source_sha", "runtime_tree_sha256", "image_id", "schema_sha256",
                      "dataset_sha256", "workload_sha256"):
            changed = identity()
            changed[field] = changed[field].replace(changed[field][-1], "9")
            self.assertNotEqual(provenance.seal(changed)["identity_sha256"], baseline["identity_sha256"])
        changed = identity()
        changed["config"]["app_memory_mib"] = 1024
        self.assertNotEqual(provenance.seal(changed)["identity_sha256"], baseline["identity_sha256"])
        reordered = dict(reversed(list(identity().items())))
        self.assertEqual(provenance.seal(reordered), baseline)
        for changed in ({**identity(), "cookie": "sentinel"},
                        {**identity(), "runtime": "elixir-1.18.3-otp-27"},
                        {**identity(), "config": {**identity()["config"], "password": "sentinel"}},
                        {**identity(), "source_sha": "dirty"}):
            with self.assertRaises(ValueError):
                provenance.seal(changed)

    def test_control_plan_matches_caps_labels_context_and_bounded_schedule(self):
        """benchmark controls match caps labels context and bounded schedule"""
        names = {role: "probe-" + role for role in ("rails", "hybrid", "db", "redis", "client", "network")}
        images = {role: "sha256:" + "c" * 64 for role in ("rails", "hybrid", "db", "redis", "client")}
        result = control.plan("probe", names, images, {"rails": "/src/rails", "hybrid": "/src/hybrid"},
                              {"rails": "/private/app.env", "hybrid": "/private/app.env",
                               "db": "/private/db.env"}, manifest())
        self.assertEqual(result["measured_trials"], 240)
        self.assertEqual(result["minimum_seconds"], 20400)
        self.assertEqual(len(result["schedule"]), 120)
        self.assertEqual([r["app"] for r in result["schedule"][:2]], ["rails", "hybrid"])
        self.assertEqual([r["app"] for r in result["schedule"][20:22]], ["hybrid", "rails"])
        for cmd in result["commands"]:
            self.assertEqual(cmd[:3], ["docker", "--context", "orbstack"])
            if "create" in cmd:
                self.assertIn(ownership.OWNER_KEY + "=probe", cmd)
            if "--memory" in cmd:
                self.assertEqual(cmd[cmd.index("--memory") + 1], cmd[cmd.index("--memory-swap") + 1])
        self.assertFalse(any(c[3] in {"run", "start", "build"} for c in result["commands"]))
        self.assertTrue(all(c[:3] == ["docker", "--context", "orbstack"] for c in result["build_commands"]))
        self.assertEqual(len(result["build_commands"]), 2)
        self.assertIn("ELIXIR_VERSION=1.20.4", result["build_commands"][1])
        self.assertFalse(any("-p" in c or "--publish" in c or "-e" in c for c in result["commands"]))
        for field, value in (("repetitions", 4), ("trial_seconds", 600), ("max_vus", 64)):
            bad = copy.deepcopy(manifest())
            bad[field] = value
            with self.assertRaises(ValueError):
                control.plan("probe", names, images, {}, {}, bad)

    def test_comparison_refuses_unequal_seed_schema_and_runtime_budgets(self):
        """benchmark comparison refuses unequal seed schema and runtime budgets"""
        left, right = identity(), identity()
        right["runtime"] = "ruby-3.4.9-yjit"
        right["source_sha"] = "9" * 40
        self.assertTrue(provenance.matched_controls(left, right))
        for field in ("schema_sha256", "dataset_sha256", "workload_sha256"):
            changed = {**right, field: "9" * 64}
            self.assertFalse(provenance.matched_controls(left, changed))
        changed = {**right, "config": {**right["config"], "app_memory_mib": 1024}}
        self.assertFalse(provenance.matched_controls(left, changed))
        with self.assertRaises(ValueError):
            provenance.matched_controls(left, {**right, "connection": "SYNTHETIC_PRIVATE"})

    def test_command_line_requires_dry_run_and_never_invokes_docker(self):
        """benchmark command line requires dry-run and never invokes Docker"""
        with tempfile.TemporaryDirectory() as directory:
            trap = pathlib.Path(directory) / "docker"
            marker = pathlib.Path(directory) / "invoked"
            trap.write_text('#!/bin/sh\nprintf invoked > "' + str(marker) + '"\nexit 90\n')
            trap.chmod(0o700)
            env = {**os.environ, "PATH": directory, "DATABASE_PASSWORD": "SYNTHETIC_ENV_PRIVATE"}
            result = subprocess.run([sys.executable, str(ROOT / "cli.py"), "--dry-run"],
                                    capture_output=True, text=True, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            output = json.loads(result.stdout)
            self.assertEqual(output["mode"], "dry-run")
            self.assertEqual(output["measured_trials"], 240)
            self.assertNotIn("SYNTHETIC_ENV_PRIVATE", result.stdout + result.stderr)
            refused = subprocess.run([sys.executable, str(ROOT / "cli.py")], capture_output=True, env=env)
            self.assertNotEqual(refused.returncode, 0)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
