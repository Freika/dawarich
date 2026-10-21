import argparse
import json
import pathlib

from control import plan


def main():
    parser = argparse.ArgumentParser(description="Render control commands; execution is a D1 handoff")
    parser.add_argument("--dry-run", action="store_true", required=True)
    parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent
    names = {role: "preview-" + role for role in ("rails", "hybrid", "db", "redis", "client", "network")}
    images = {role: "sha256:" + str(i) * 64
              for i, role in enumerate(("rails", "hybrid", "db", "redis", "client"), 1)}
    contexts = {"rails": "${RAILS_CONTROL_SOURCE}", "hybrid": "${HYBRID_CONTROL_SOURCE}"}
    env_files = {"rails": "${RAILS_PRIVATE_ENV_FILE}", "hybrid": "${PHOENIX_PRIVATE_ENV_FILE}",
                 "db": "${POSTGRES_PRIVATE_ENV_FILE}"}
    result = plan("preview", names, images, contexts, env_files, json.loads((root / "workload.json").read_text()))
    encoded = json.dumps(result, indent=2)
    for role, name in names.items():
        encoded = encoded.replace(name, "${BENCH_" + role.upper() + "_NAME}")
    for role, image in images.items():
        encoded = encoded.replace(image, "${BENCH_" + role.upper() + "_IMAGE_ID}")
    encoded = encoded.replace("=preview", "=${BENCH_RUN_ID}")
    print(encoded)


if __name__ == "__main__":
    main()
