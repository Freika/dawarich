defmodule Dawarich.Visits.PlaceFinder do
  @moduledoc false

  alias Dawarich.{RailsEffects, RubyDecimal}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @default_name "Suggested place"

  @insert_sql """
  INSERT INTO places (user_id, name, geodata, latitude, longitude, lonlat, source, created_at, updated_at)
  VALUES ($1, $2, '{}', $3::text::numeric, $4::text::numeric,
          ST_SetSRID(ST_MakePoint($4::text::numeric::float8, $3::text::numeric::float8), 4326)::geography, 1, now(), now())
  RETURNING id
  """

  def mint(repo, user_id, lat, lon, suggested_name, geocoding_enabled) do
    name = if Ruby.present?(suggested_name), do: suggested_name, else: @default_name

    if length(String.codepoints(name)) > 255,
      do: raise(ArgumentError, "Validation failed: Name is too long (maximum is 255 characters)")

    {:ok, id} =
      repo.transaction(fn ->
        [[id]] =
          repo.query!(
            @insert_sql,
            [user_id, name, RubyDecimal.column(lat, 10, 6), RubyDecimal.column(lon, 10, 6)],
            log: false
          ).rows

        if geocoding_enabled, do: RailsEffects.place_name(repo, user_id, id)
        id
      end)

    id
  end
end
