OWNER_KEY = "org.dawarich.benchmark.run"
HARNESS_KEY = "org.dawarich.benchmark.harness"
HARNESS = "native-frontend-v1"


class Refusal(RuntimeError):
    pass


class Docker:
    def __init__(self, run_id, resources, runner):
        if not valid_name(run_id) or set(resources) != {"container", "network"}:
            raise Refusal("invalid ownership scope")
        names = [name for group in resources.values() for name in group]
        if len(names) != len(set(names)) or not names:
            raise Refusal("invalid resource list")
        if any(not valid_name(n) or not n.startswith(run_id + "-") for n in names):
            raise Refusal("resource outside run namespace")
        self.run_id = run_id
        self.resources = {kind: tuple(resources[kind]) for kind in ("container", "network")}
        self.runner = runner

    def cleanup(self):
        owned = []
        for kind, names in self.resources.items():
            for name in names:
                record = self.inspect(kind, name)
                if record is None:
                    continue
                labels = record.get("Labels") or {}
                if labels.get(OWNER_KEY) != self.run_id or labels.get(HARNESS_KEY) != HARNESS:
                    raise Refusal("cleanup ownership mismatch")
                if record.get("Running") is not False:
                    raise Refusal("stop owned services before cleanup")
                resource_id = record.get("Id")
                if not valid_name(resource_id):
                    raise Refusal("missing immutable resource identity")
                owned.append((kind, resource_id))
        commands = []
        for kind, resource_id in owned:
            args = ["rm", resource_id] if kind == "container" else ["network", "rm", resource_id]
            command = docker_command(*args)
            self.call(command)
            commands.append(command)
        return commands

    def require_absent(self):
        for kind, names in self.resources.items():
            for name in names:
                if self.inspect(kind, name) is not None:
                    raise Refusal("existing resource must be preserved")

    def inspect(self, kind, name):
        labels = ".Config.Labels" if kind == "container" else ".Labels"
        running = '{{json .State.Running}}' if kind == "container" else 'false'
        projection = '{"Id":{{json .Id}},"Labels":{{json ' + labels + '}},"Running":' + running + '}'
        args = ["container" if kind == "container" else "network", "inspect", "--format", projection, name]
        try:
            result = self.runner(docker_command(*args), capture_output=True, text=True, check=False)
            if result.returncode != 0:
                missing = re.fullmatch(
                    r"(?:Error(?: response from daemon)?: )?No such (?:object|container|network|resource)(?:: "
                    + re.escape(name) + r")?", result.stderr.strip())
                if missing and not result.stdout.strip():
                    return None
                raise Refusal("Docker inspection unavailable")
            record = json.loads(result.stdout)
            if not isinstance(record, dict):
                raise Refusal("invalid resource projection")
            return record
        except Refusal:
            raise
        except Exception:
            raise Refusal("Docker inspection failed") from None

    def call(self, command):
        try:
            result = self.runner(command, capture_output=True, text=True, check=False)
            if result.returncode != 0:
                raise Refusal("Docker command failed; output suppressed")
        except Refusal:
            raise
        except Exception:
            raise Refusal("Docker command failed; output suppressed") from None


def valid_name(value):
    return isinstance(value, str) and re.fullmatch(r"[a-z0-9][a-z0-9_.-]{0,95}", value) is not None


def docker_command(*args):
    return ["docker", "--context", "orbstack", *args]
import json
import re
