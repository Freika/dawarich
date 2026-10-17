# Family location addresses

`GET /api/v1/families/locations` includes an additive, nullable `address` string on each location:

```json
{
  "user_id": 7,
  "latitude": 51.0,
  "longitude": 12.0,
  "timestamp": 1791547200,
  "address": "Example Street 12, Example City"
}
```

The label describes the same point as the coordinates and timestamp. It uses stored Photon, Geoapify, Nominatim or LocationIQ data, falling back to the point's city/country when street details are unavailable. Raw provider metadata is not exposed. A label is an approximate description of the last known location, not evidence that someone is inside a particular building.

When a latest shared point has neither geodata nor a completed geocoding attempt, the response queues the existing reverse-geocoding job. The member's configured provider, provider rate limiter and point-level duplicate-job claim are reused. No external provider request runs in the family API request. Stored point data is reused on subsequent polls; completed empty results are not repeatedly queued. Worker/queue errors leave the location response available.

New street lookups require geocoding to be configured, geodata storage enabled (`STORE_GEODATA`), and a worker processing the `reverse_geocoding` queue. With storage disabled, existing city/country values can still supply a locality label. Missing results are `null`; clients should keep showing coordinates and the point timestamp, then use the address from a later location refresh. Clients must not carry an old address over to different coordinates.

Existing family membership, plan and sharing-expiry checks still control access. No schema migration, new credentials, new public geocoding endpoint or client-side geocoding provider is required. Old clients ignore the new field; new clients should accept older servers that omit it.
