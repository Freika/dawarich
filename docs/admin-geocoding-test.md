# Admin geocoding connection test

The **Instance settings → Geocoding → Test connection** form makes one reverse lookup using the currently resolved instance provider. Administrators can enter latitude and longitude within the regional coverage of that provider (for example, a Photon index containing only US data).

- Both fields are optional as a pair. Leaving both blank uses the existing default `[51.3402, 12.3712]` (latitude, longitude).
- A supplied pair must contain finite decimal numbers: latitude from −90 to 90, longitude from −180 to 180, inclusive. Zero and negative values are valid. Scientific notation is accepted; surrounding whitespace is ignored.
- Partial pairs, nonnumeric values and out-of-range coordinates produce a translated error before any provider lookup. Browser number inputs also enforce ranges.
- Coordinates apply only to that test request. They are not persisted as instance settings.
- The saved provider, provider precedence, request limit (one result), five-second wait budget and provider failure messages remain unchanged.

`POST /admin/settings/test_geocoding` accepts optional top-level `latitude` and `longitude` parameters. HTML requests redirect with status 303 and a notice or alert; Turbo requests return a flash stream and retain the form inputs. Existing `Geocoding::ProviderTest.call` and `.call(config)` callers use the default coordinates. Callers can supply `.call(config, latitude: ..., longitude: ...)`.

Verification: `bundle exec rspec spec/services/geocoding spec/requests/admin/settings_spec.rb` covers coordinate parsing, inclusive boundaries, malformed input, default compatibility, access control, provider HTTP query parameters, HTML/Turbo responses, accessible labels and translations. External provider HTTP calls are stubbed. Manual browser verification should exercise a valid pair, a partial pair, browser range validation and a blank pair on desktop and mobile, including repeated submissions.

Related: [issue #3714](https://github.com/Freika/dawarich/issues/3714). The corresponding [AFFiNE page](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/zocefPoFUwVmVAcxo-BLo) is titled **Dawarich — Admin geocoding connection test**; this file is the versioned source.

The form uses a submit button rather than the Rails submit-input helper: the latter adds `data-disable-with`, which conflicts with Turbo and can leave the control disabled after a stream response when Rails UJS is also loaded.
