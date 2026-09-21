import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = await readFile(
  new URL(
    "../../app/javascript/maps_maplibre/utils/time_overlap.js",
    import.meta.url,
  ),
  "utf8",
)
const { timeOverlapOpacityExpr } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
)

function evaluate(expression, properties) {
  if (!Array.isArray(expression)) return expression
  const [operator, ...arguments_] = expression
  const values = () => arguments_.map((value) => evaluate(value, properties))
  switch (operator) {
    case "case":
      return evaluate(arguments_[0], properties)
        ? evaluate(arguments_[1], properties)
        : evaluate(arguments_[2], properties)
    case "all":
      return values().every(Boolean)
    case "has":
      return Object.hasOwn(properties, arguments_[0])
    case "get":
      return properties[arguments_[0]]
    case "<=": {
      const [left, right] = values()
      return left <= right
    }
    case ">=": {
      const [left, right] = values()
      return left >= right
    }
    default:
      throw new Error(`Unsupported expression: ${operator}`)
  }
}

test("a mixed-day point aggregate stays visible on each overlapping day", () => {
  const expression = timeOverlapOpacityExpr(
    "timestamp",
    "max_timestamp",
    200,
    299,
    1,
    0.04,
  )

  assert.equal(evaluate(expression, { timestamp: 100, max_timestamp: 250 }), 1)
  assert.equal(
    evaluate(expression, { timestamp: 100, max_timestamp: 150 }),
    0.04,
  )
})

test("a track spanning midnight remains visible on its second day", () => {
  const expression = timeOverlapOpacityExpr(
    "start_timestamp",
    "end_timestamp",
    200,
    299,
    1,
    0.04,
  )

  assert.equal(
    evaluate(expression, { start_timestamp: 190, end_timestamp: 210 }),
    1,
  )
  assert.equal(
    evaluate(expression, { start_timestamp: 100, end_timestamp: 190 }),
    0.04,
  )
})
