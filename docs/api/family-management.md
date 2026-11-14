# Family management API

Family management uses the same JSON endpoints on self-hosted and Cloud
instances. Authenticate every request with `Authorization: Bearer <api_key>`.
This API administers membership; it does not return locations or change consent
to share location/history. Existing `/api/v1/families/mine`, sharing, location and
location-request endpoints remain unchanged.

## Hosting and access

Self-hosted families require no subscription and have no member limit. Cloud
families require live Family access to create, rename, invite or accept an
invitation; the limit is five people total, including the owner. Pending,
unexpired invitations reserve seats. Accepting an invitation converts its
reservation into membership, including the fifth seat.

The per-user family feature setting gates creation, renaming and sending
invitations. Accepting an invitation checks the invited email and the family's
live access rather than requiring the invitee to already hold a Family plan.
Authenticated users awaiting payment may inspect and accept their invitation.
They cannot bypass payment gating for other management endpoints.

After access lapses, authenticated owners can still inspect management state,
list/revoke pending invitations, remove members, and delete their empty family.
Members can leave. These cleanup operations also remain available when the
family feature setting is off. Owners must remove other members before deleting
the family and cannot leave their own membership. Membership removal uses the
existing cleanup service, including revoking inherited Cloud access and stopping
the departing member's sharing.

## Endpoints

All paths below start with `/api/v1/families`.

| Method | Path | Request | Success |
| --- | --- | --- | --- |
| GET | `/manage` | — | 200, management state |
| POST | `/manage` | `{"family":{"name":"Our family"}}` | 201, management state |
| PATCH | `/manage` | `{"family":{"name":"New name"}}` | 200, management state |
| DELETE | `/manage` | — | 204, owner only, no other members |
| GET | `/invitations` | — | 200, `{"invitations":[...]}`, owner only |
| POST | `/invitations` | `{"family_invitation":{"email":"member@example.com"}}` | 201, `{"invitation":{...}}`, owner only |
| GET | `/invitations/:token` | — | 200, `{"invitation":{...}}`, invitee or family owner |
| DELETE | `/invitations/:token` | — | 204, owner only, pending invitation |
| POST | `/invitations/:token/accept` | — | 200, family and membership |
| DELETE | `/members/:id` | — | 204, owner removing a member, or member removing self |
| DELETE | `/membership` | — | 204, leave current family |

`:id` is a **membership ID**, not a user ID. Owner mutations and invitation
revocation always scope records to the authenticated user's family. Invitation
tokens are opaque: a different account receives 404 even if it knows the token.
Do not put API keys in invitation URLs. Token inspection does not accept or
consume the invitation.

### Management state

```json
{
  "self_hosted": false,
  "feature_enabled": true,
  "entitled": true,
  "family": {"id": 12, "name": "Our family", "access_live": true},
  "me": {"membership_id": 31, "user_id": 7, "owner": true},
  "capacity": {"limit": 5, "members": 1, "pending_invitations": 0},
  "members": [{"id": 31, "user_id": 7, "name": "Alex", "role": "owner"}]
}
```

Without membership, `family` and `me` are `null`, member and invitation counts
are zero, and `members` is empty. On self-hosted instances `capacity.limit` is
`null`. Owners receive the roster needed to remove members, including after
lapse; nonowners receive only their own membership row. Names are display names
and may fall back to the account email. No locations are included.

### Invitation

```json
{
  "invitation": {
    "token": "opaque-invitation-token",
    "email": "member@example.com",
    "status": "pending",
    "expires_at": "2026-11-18T12:00:00Z",
    "family": {"id": 12, "name": "Our family"},
    "acceptance_available": true
  }
}
```

`acceptance_available` reports whether the invitation is pending/unexpired and
its family's access is live. Acceptance revalidates email, existing membership,
capacity and paid period under the existing service's locks; the displayed
value does not guarantee acceptance. Expired/processed invitations remain
inspectable by authorized accounts, with `acceptance_available: false`.
The owner invitation list contains only pending, unexpired invitations.

Acceptance returns:

```json
{
  "family": {"id": 12, "name": "Our family"},
  "membership": {"id": 32, "user_id": 8, "role": "member"}
}
```

## Errors and retries

- 401: missing or invalid API key.
- 402: account awaits payment (except invitation inspection/acceptance).
- 403: `forbidden` for failed role/email/status authorization;
  `feature_disabled` or `family_plan_required` for a gated action.
- 404: no current family/membership, unknown record, record outside the current
  family, or an invitation the account cannot inspect.
- 400: `parameter_missing`, with `message`, for a missing/malformed request wrapper.
- 422: `validation_failed`, with `message`, for invalid names/emails, full
  families, duplicate invitations, a lapsed family during acceptance, owner
  departure, or attempting to delete a family that still has other members.

Existing API authentication/feature-gate errors keep their existing format.
Management validation and parameter errors use the codes above. Treat messages
as explanatory text rather than machine-readable identifiers. An expired or
already processed invitation is rejected by authorization (403) on acceptance.
A successful deletion returns an empty body. Retrying a completed membership or
family deletion returns 404; inspect management state after an uncertain network
result. These endpoints do not create, upgrade or cancel store subscriptions.

## Example

Use a synthetic test account and substitute a test-only key:

```sh
curl --request POST 'https://dawarich.example/api/v1/families/manage' \
  --header 'Authorization: Bearer TEST_API_KEY' \
  --header 'Content-Type: application/json' \
  --data '{"family":{"name":"Our family"}}'

curl --request POST 'https://dawarich.example/api/v1/families/invitations' \
  --header 'Authorization: Bearer TEST_API_KEY' \
  --header 'Content-Type: application/json' \
  --data '{"family_invitation":{"email":"member@example.com"}}'
```

No schema migration or new server configuration is required. Older servers may
return 404 for the management endpoints; clients should retain website management
as a fallback and distinguish unsupported APIs from an absent family using the
successful `/manage` response's nullable `family` field.
