# Standalone shared points

The public shared-points API accepts equal timestamps, matching
`Api::V1::Shared::PointsController`. Timestamp equality is not a validation
error and does not send a standalone request back to Rails.

Timeline, trip, track and live-route reads apply their existing resource and
privacy filters before counting and sampling. Sampling uses a timestamp-ordered
SQL row number and `ceil(total / 10_000)` stride, including when timestamps tie.
Rails does not promise an order between tied rows; Phoenix preserves that
contract. Live position selects one latest non-anomalous point before checking
freshness and privacy, as Rails does.

`StandaloneSharePointsFlowTest` creates a timeline share through the actual
form, opens its public page and reads the API with tied timestamps. It checks
owner/date/anomaly boundaries and 10,001-point stride sampling. Its live test
checks current position and route with tied latest timestamps. Existing shared
API tests retain privacy, freshness, entitlement and cache coverage.

Shared engineering index: AFFiNE, Dawarich standalone journey sweep and
integration documentation. The sweep-2 fix report records RED/GREEN/mutation
and final gate evidence.
