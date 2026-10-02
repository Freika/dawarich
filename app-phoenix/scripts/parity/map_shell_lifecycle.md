# Map shell browser regression

`map_shell_lifecycle.spec.js` checks Phoenix's map bridge lifecycle. Run it
against the isolated Phoenix/Puma stand with the existing authenticated
Playwright demo state. Its helper imports resolve from the root of the
Playwright repository, so copy the spec into the private test checkout:

```sh
cp "$task_source/app-phoenix/scripts/parity/map_shell_lifecycle.spec.js" \
  "$E2E_REPO/map_shell_lifecycle.spec.js"
cd "$E2E_REPO"
BASE_URL=http://127.0.0.1:3120 E2E_WORKERS=1 \
  npx playwright test map_shell_lifecycle.spec.js \
  --project=chromium --no-deps --reporter=line
```

The three cases cover same-document Back/Forward replacement, a real controller
asset finishing after unmount, and a shell import finishing after its hook root
has detached. Asset routes delay the actual responses; they do not substitute
controller implementations. No fixed sleeps, retries or extended test timeouts
are required. This is a Phoenix-specific contract probe; the canonical Rails
page acceptance specs remain in the Playwright repository.
