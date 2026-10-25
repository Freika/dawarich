let translations

function loadTranslations() {
  if (typeof document === "undefined") return {}
  const element = document.getElementById("i18n-translations")
  if (!element) return {}

  try {
    return JSON.parse(element.textContent)
  } catch (_error) {
    return {}
  }
}

function currentTranslations() {
  if (translations && Object.keys(translations).length > 0) return translations

  translations = loadTranslations()
  return translations
}

function interfaceLocale() {
  return typeof document === "undefined"
    ? undefined
    : document.documentElement?.lang || undefined
}

function pluralCategory(count) {
  return new Intl.PluralRules(interfaceLocale()).select(Number(count))
}

export function translate(key, values = {}) {
  let value = key
    .split(".")
    .reduce((current, part) => current?.[part], currentTranslations())
  if (value && typeof value === "object" && values.count !== undefined) {
    value = value[pluralCategory(values.count)] ?? value.other
  }
  if (typeof value !== "string") return key

  return value.replace(
    /%\{([^}]+)\}/g,
    (_match, name) => values[name] ?? `%{${name}}`,
  )
}

export function formatNumber(value) {
  return new Intl.NumberFormat(interfaceLocale()).format(value)
}

const DEFAULT_PREFERENCES = {
  date_format: "auto",
  time_format: "auto",
  first_day_of_week: "monday",
}

const DATE_PRESETS = {
  "dd.mm.yyyy": ({ day, month, year }) => `${day}.${month}.${year}`,
  "dd/mm/yyyy": ({ day, month, year }) => `${day}/${month}/${year}`,
  "mm/dd/yyyy": ({ day, month, year }) => `${month}/${day}/${year}`,
  "yyyy-mm-dd": ({ day, month, year }) => `${year}-${month}-${day}`,
}

const INVALID_DATE = "Invalid Date"
let parsedPreferences = { content: null, value: DEFAULT_PREFERENCES }

function preferences() {
  const meta =
    typeof document === "undefined"
      ? null
      : document.querySelector?.('meta[name="date-time-preferences"]')
  if (!meta?.content) return DEFAULT_PREFERENCES
  if (meta.content === parsedPreferences.content) return parsedPreferences.value

  let value = DEFAULT_PREFERENCES
  try {
    value = { ...DEFAULT_PREFERENCES, ...JSON.parse(meta.content) }
  } catch (_error) {}
  parsedPreferences = { content: meta.content, value }
  return value
}

function validDate(value) {
  const date = new Date(value)
  return Number.isNaN(date.valueOf()) ? null : date
}

function numericParts(date, options) {
  return Object.fromEntries(
    new Intl.DateTimeFormat("en-US", { ...options, numberingSystem: "latn" })
      .formatToParts(date)
      .filter((part) => part.type !== "literal")
      .map((part) => [part.type, part.value]),
  )
}

export function formatDate(
  value,
  { timeZone, month = "short", locale = interfaceLocale() } = {},
) {
  const date = validDate(value)
  if (!date) return INVALID_DATE

  const preset = DATE_PRESETS[preferences().date_format]
  if (preset) {
    return preset(
      numericParts(date, {
        day: "2-digit",
        month: "2-digit",
        year: "numeric",
        timeZone,
      }),
    )
  }

  return new Intl.DateTimeFormat(locale, {
    day: "numeric",
    month,
    year: "numeric",
    timeZone,
  }).format(date)
}

export function formatTime(value, { seconds = false, timeZone } = {}) {
  const date = validDate(value)
  if (!date) return INVALID_DATE

  const { hour, minute, second } = numericParts(date, {
    hour: "2-digit",
    minute: "2-digit",
    second: seconds ? "2-digit" : undefined,
    hourCycle: "h23",
    timeZone,
  })
  const tail = seconds ? `:${minute}:${second}` : `:${minute}`

  if (preferences().time_format !== "12h") return `${hour}${tail}`

  const hours = Number(hour)
  return translate("date_time_preferences.clock_12h", {
    time: `${hours % 12 || 12}${tail}`,
    meridiem: translate(
      `date_time_preferences.meridiem.${hours < 12 ? "am" : "pm"}`,
    ),
  })
}

export function formatDateTime(value, options = {}) {
  if (!validDate(value)) return INVALID_DATE

  return `${formatDate(value, options)}, ${formatTime(value, options)}`
}

export function usesDatePreset() {
  return Boolean(DATE_PRESETS[preferences().date_format])
}

export function firstDayOfWeek() {
  return preferences().first_day_of_week === "sunday" ? 0 : 1
}
