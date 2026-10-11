import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import test from "node:test"

for (const reason of ["reset", "destroy"]) {
  test(`a ${reason} scope consumes a late rejected refresh promise`, () => {
    const script = `
      import { createRequestScope, cancelled } from "./app-phoenix/assets/js/map/data/request_scope.js"
      const scope = createRequestScope()
      const operation = scope.begin()
      scope.${reason}()
      try { await operation.wait(Promise.reject(cancelled())) } catch (error) {
        if (error.name !== "AbortError") throw error
      } finally { operation.close(); scope.destroy() }
      await new Promise(setImmediate)
    `
    const result = spawnSync(process.execPath, ["--input-type=module", "-e", script], {
      cwd: new URL("../../", import.meta.url), encoding: "utf8",
    })
    assert.equal(result.status, 0, result.stderr)
  })
}
