# Disputed areas

`disputed_areas.geojson` is derived from Natural Earth 1:10m
`ne_10m_admin_0_disputed_areas` (v5.1.2). Natural Earth data is in the public
domain. See https://www.naturalearthdata.com/about/terms-of-use/.

Achievements credit no country or region for time spent inside these areas.
Coordinates are rounded to five decimals and only `name` and `ne_brk_a3` are
kept. Features that are not territorial claims, or that are whole territories
with their own achievement card, are left out by their Natural Earth `BRK_A3`:

- Leases and buffer zones: B10, B11, B40, B43, B44, B49, B50, B84
- Settled or no longer claimed: B21, B38
- Without a recorded claim: B51, B82, B91, B95, B96, C04
- Whole territories with their own card: B12, B28, B32, B33, B53, B54, B55, B69, B77
