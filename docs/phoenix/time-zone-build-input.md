# Time-zone build input

Rails selects `TZInfo::DataSource.set(:ruby)` immediately after loading its gems.
`tzinfo-data` is installed on every platform and pinned in `Gemfile.lock`; the
image's operating-system zoneinfo files do not determine Rails' time-zone choices.

`phoenix:time_zones` exports the Settings helper's choices and the installed
`tzinfo_data_version` into one JSON file. Phoenix compiles those choices from
`app-phoenix/priv/time_zones.json`. The Rails and ExUnit build-input tests reject
a snapshot whose source version differs from the lockfile.

Labels use Rails' `formatted_offset`, based on TZInfo's `base_utc_offset`, rather
than the observed DST offset. Winter/summer regression coverage includes Dublin,
whose standard offset is +01:00 in the bundled IANA data.

After changing `tzinfo-data`, run `phoenix:time_zones` with the committed snapshot
path, then the existing settings fixture generator's named corpus/page examples.
Run the generator twice and compare the bytes, the build-input tests, and
`app-phoenix/scripts/compare_build_inputs.sh` against the candidate's Rails export.
`time_zone_names.json` mirrors ActiveSupport's static name mapping and is not
derived from TZInfo's data source.
