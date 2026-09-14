import { execFileSync } from "node:child_process"

export default function globalTeardown() {
  execFileSync(
    "asdf",
    ["exec", "bundle", "exec", "rails", "runner", "e2e/setup/cleanup.rb"],
    {
      cwd: process.cwd(),
      env: {
        ...process.env,
        RAILS_ENV: "test",
        DATABASE_NAME:
          process.env.MAP_E2E_DATABASE_NAME || "dawarich_tile_only_e2e_test",
      },
      stdio: "inherit",
    },
  )
}
