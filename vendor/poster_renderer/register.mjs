import { register } from "node:module"

register(new URL("./loader.mjs", import.meta.url))
