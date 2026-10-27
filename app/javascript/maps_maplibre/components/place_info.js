import { translate } from "i18n"

function escapeText(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => {
    return {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    }[character]
  })
}

function parseTags(value) {
  try {
    const tags = typeof value === "string" ? JSON.parse(value) : value
    return Array.isArray(tags) ? tags.filter((tag) => tag?.name) : []
  } catch {
    return []
  }
}

export function buildPlaceInfo(properties) {
  const tags = parseTags(properties.tags)
    .map((tag) => {
      const color = /^#[\da-f]{3,8}$/i.test(tag.color) ? tag.color : null
      const style = color
        ? ` style="color: ${color}; border-color: ${color}"`
        : ""
      return `<span class="badge badge-outline h-auto max-w-full whitespace-normal [overflow-wrap:anywhere]" data-testid="place-tag"${style}>${escapeText(tag.icon)} #${escapeText(tag.name)}</span>`
    })
    .join("")
  const note = properties.note || properties.description
  const content = `
    <div class="space-y-2 [overflow-wrap:anywhere]">
      ${tags ? `<div class="flex flex-wrap gap-2">${tags}</div>` : ""}
      ${note ? `<div>${escapeText(note)}</div>` : ""}
      ${properties.visitRadius ? `<div><span class="font-semibold">${escapeText(translate("map_info.visit_radius"))}:</span> ${Math.round(properties.visitRadius)}m</div>` : ""}
      ${properties.nameLocked ? `<div class="text-xs opacity-70" data-testid="place-name-lock">${escapeText(translate("map_info.place_name_locked"))}</div>` : ""}
    </div>
  `
  const id = properties.id
  const actions = id
    ? [
        {
          type: "button",
          handler: "openPlace",
          id,
          entityType: "place",
          label: translate("places.open"),
        },
        {
          type: "button",
          handler: "openPlace",
          id,
          entityType: "place",
          label: translate("messages.edit"),
        },
        {
          type: "button",
          handler: "openPlace",
          id,
          entityType: "place",
          label: translate("messages.delete"),
        },
      ]
    : []

  return {
    title: properties.name || translate("map_info.place"),
    content,
    actions,
  }
}
