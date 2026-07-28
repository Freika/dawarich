// Display prices only — Stripe charges the price configured server-side.
export const PRINT_PRODUCTS = {
  "print-30x40": { sku: "poster-30x40", priceLabel: "€34.99" },
  "print-50x70": { sku: "poster-50x70", priceLabel: "€54.99" },
  "print-70x100": { sku: "poster-70x100", priceLabel: "€74.99" },
}

// Orderable layout ids, in display order — drives the size picker shown when
// the current layout can't be ordered.
export const ORDERABLE_LAYOUT_IDS = Object.keys(PRINT_PRODUCTS)

export function printProductFor(layoutId) {
  return PRINT_PRODUCTS[layoutId] || null
}
