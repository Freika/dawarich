const TOOLTIP_SELECTOR = ".tooltip[data-tip]"
const TOOLTIP_OFFSET = 10
const VIEWPORT_PADDING = 8
const INTERACTIVE_SELECTOR = 'a, button, input, select, textarea, summary, [tabindex]'

let tooltipPopover
let activeTrigger
let isOpen = false
const activeReasons = new Set()

const supportsPopoverTooltips = () =>
  typeof HTMLElement !== "undefined" &&
  "showPopover" in HTMLElement.prototype &&
  "hidePopover" in HTMLElement.prototype

const canHover = () =>
  typeof window.matchMedia !== "function" || window.matchMedia("(hover: hover)").matches

function ensureTooltipPopover() {
  if (tooltipPopover?.isConnected) return tooltipPopover

  tooltipPopover = document.createElement("div")
  tooltipPopover.id = "app-tooltip-popover"
  tooltipPopover.setAttribute("popover", "manual")
  tooltipPopover.setAttribute("role", "tooltip")
  tooltipPopover.className = "app-tooltip-popover"
  document.body.appendChild(tooltipPopover)

  return tooltipPopover
}

function resolvePlacement(trigger) {
  if (trigger.classList.contains("tooltip-bottom")) return "bottom"
  if (trigger.classList.contains("tooltip-left")) return "left"
  if (trigger.classList.contains("tooltip-right")) return "right"

  return "top"
}

function resolveAnchor(trigger, target) {
  if (!(target instanceof Element)) return trigger

  const interactiveTarget = target.closest(INTERACTIVE_SELECTOR)
  if (interactiveTarget && trigger.contains(interactiveTarget)) return interactiveTarget

  return trigger.contains(target) ? target : trigger
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function pickPlacement(anchorRect, desiredPlacement, popoverRect) {
  const availableSpace = {
    top: anchorRect.top - VIEWPORT_PADDING,
    right: window.innerWidth - anchorRect.right - VIEWPORT_PADDING,
    bottom: window.innerHeight - anchorRect.bottom - VIEWPORT_PADDING,
    left: anchorRect.left - VIEWPORT_PADDING
  }

  if (desiredPlacement === "top" && availableSpace.top < popoverRect.height + TOOLTIP_OFFSET) {
    return availableSpace.bottom > availableSpace.top ? "bottom" : desiredPlacement
  }

  if (desiredPlacement === "bottom" && availableSpace.bottom < popoverRect.height + TOOLTIP_OFFSET) {
    return availableSpace.top > availableSpace.bottom ? "top" : desiredPlacement
  }

  if (desiredPlacement === "left" && availableSpace.left < popoverRect.width + TOOLTIP_OFFSET) {
    return availableSpace.right > availableSpace.left ? "right" : desiredPlacement
  }

  if (desiredPlacement === "right" && availableSpace.right < popoverRect.width + TOOLTIP_OFFSET) {
    return availableSpace.left > availableSpace.right ? "left" : desiredPlacement
  }

  return desiredPlacement
}

function positionTooltip(trigger, target) {
  if (!tooltipPopover) return

  const anchor = resolveAnchor(trigger, target)
  const anchorRect = anchor.getBoundingClientRect()
  const popoverRect = tooltipPopover.getBoundingClientRect()
  const placement = pickPlacement(anchorRect, resolvePlacement(trigger), popoverRect)
  let top
  let left

  switch (placement) {
    case "bottom":
      top = anchorRect.bottom + TOOLTIP_OFFSET
      left = anchorRect.left + anchorRect.width / 2 - popoverRect.width / 2
      break
    case "left":
      top = anchorRect.top + anchorRect.height / 2 - popoverRect.height / 2
      left = anchorRect.left - popoverRect.width - TOOLTIP_OFFSET
      break
    case "right":
      top = anchorRect.top + anchorRect.height / 2 - popoverRect.height / 2
      left = anchorRect.right + TOOLTIP_OFFSET
      break
    default:
      top = anchorRect.top - popoverRect.height - TOOLTIP_OFFSET
      left = anchorRect.left + anchorRect.width / 2 - popoverRect.width / 2
      break
  }

  tooltipPopover.dataset.placement = placement
  tooltipPopover.style.top = `${Math.round(clamp(top, VIEWPORT_PADDING, window.innerHeight - popoverRect.height - VIEWPORT_PADDING))}px`
  tooltipPopover.style.left = `${Math.round(clamp(left, VIEWPORT_PADDING, window.innerWidth - popoverRect.width - VIEWPORT_PADDING))}px`
}

function hideActiveTooltip() {
  activeReasons.clear()
  activeTrigger = undefined

  if (!tooltipPopover || !isOpen) return

  tooltipPopover.hidePopover()
  tooltipPopover.style.visibility = ""
  isOpen = false
}

function showTooltip(trigger, target, reason) {
  const text = trigger.dataset.tip?.trim()
  if (!text) return

  if (activeTrigger && activeTrigger !== trigger) hideActiveTooltip()

  const popover = ensureTooltipPopover()
  activeTrigger = trigger
  activeReasons.add(reason)
  popover.textContent = text
  popover.style.visibility = "hidden"

  if (!isOpen) {
    popover.showPopover()
    isOpen = true
  }

  positionTooltip(trigger, target)
  popover.style.visibility = ""
}

function releaseTooltip(trigger, reason) {
  if (activeTrigger !== trigger) return

  activeReasons.delete(reason)

  if (activeReasons.size === 0) hideActiveTooltip()
}

function findTooltipTrigger(target) {
  return target instanceof Element ? target.closest(TOOLTIP_SELECTOR) : null
}

function handleMouseOver(event) {
  if (!canHover()) return

  const trigger = findTooltipTrigger(event.target)
  if (!trigger || trigger.contains(event.relatedTarget)) return

  showTooltip(trigger, event.target, "hover")
}

function handleMouseOut(event) {
  const trigger = findTooltipTrigger(event.target)
  if (!trigger || trigger.contains(event.relatedTarget)) return

  releaseTooltip(trigger, "hover")
}

function handleFocusIn(event) {
  const trigger = findTooltipTrigger(event.target)
  if (!trigger) return

  showTooltip(trigger, event.target, "focus")
}

function handleFocusOut(event) {
  const trigger = findTooltipTrigger(event.target)
  if (!trigger || trigger.contains(event.relatedTarget)) return

  releaseTooltip(trigger, "focus")
}

function initializePopoverTooltips() {
  if (!supportsPopoverTooltips() || window.__dawarichPopoverTooltipsInitialized) return

  window.__dawarichPopoverTooltipsInitialized = true
  document.documentElement.dataset.popoverTooltips = "enabled"

  document.addEventListener("mouseover", handleMouseOver)
  document.addEventListener("mouseout", handleMouseOut)
  document.addEventListener("focusin", handleFocusIn)
  document.addEventListener("focusout", handleFocusOut)
  document.addEventListener("click", hideActiveTooltip, true)
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") hideActiveTooltip()
  })
  document.addEventListener("turbo:before-cache", hideActiveTooltip)
  window.addEventListener("scroll", hideActiveTooltip, true)
  window.addEventListener("resize", hideActiveTooltip)
}

initializePopoverTooltips()
