defmodule Dawarich.Ingest.Friends do
  @moduledoc false

  alias Dawarich.Ingest.Ruby
  alias Dawarich.Repo

  @codes %{1 => 1, 5 => 1, 2 => 2, 3 => 3}
  @members """
  SELECT users.id, users.email, users.settings FROM users
  INNER JOIN family_memberships ON users.id = family_memberships.user_id
  WHERE users.deleted_at IS NULL AND family_memberships.family_id = $1
  """
  @latest """
  SELECT timestamp, battery, battery_status, ST_Y(lonlat::geometry), ST_X(lonlat::geometry) FROM points
  WHERE user_id = $1 AND timestamp IS NOT NULL AND lonlat IS NOT NULL AND (anomaly = FALSE OR anomaly IS NULL)
  ORDER BY timestamp DESC LIMIT 1
  """

  def for_user(user_id, now \\ DateTime.utc_now()) do
    case Repo.query!("SELECT family_id FROM family_memberships WHERE user_id = $1 LIMIT 1", [
           user_id
         ]).rows do
      [[family_id]] ->
        Repo.query!(@members, [family_id]).rows
        |> Enum.filter(fn [_id, _email, settings] -> sharing?(settings, now) end)
        |> Enum.reject(fn [id | _] -> id == user_id end)
        |> Enum.flat_map(&member/1)

      [] ->
        []
    end
  end

  defp sharing?(settings, now) do
    case get_in(Dawarich.UserSettings.safe(settings), ["family", "location_sharing"]) do
      %{"enabled" => true} = sharing -> open?(sharing["expires_at"], now)
      _ -> false
    end
  end

  defp open?(expires, now) do
    cond do
      Ruby.blank?(expires) -> true
      is_binary(expires) -> future?(DateTime.from_iso8601(expires), now)
      true -> Ruby.unsupported!("sharing expiry is not a string")
    end
  end

  defp future?({:ok, at, _offset}, now), do: DateTime.compare(at, now) == :gt
  defp future?(_error, _now), do: Ruby.unsupported!("sharing expiry Time.zone.parse would guess")

  defp member([id, email, _settings]) do
    case Repo.query!(@latest, [id]).rows do
      [[ts, battery, status, lat, lon]] ->
        tid = Integer.to_string(id, 36)

        [
          {:object, compact([{"_type", "card"}, {"tid", tid}, {"name", email}])},
          {:object,
           compact([
             {"_type", "location"},
             {"tid", tid},
             {"lat", lat},
             {"lon", lon},
             {"tst", ts},
             {"batt", battery},
             {"bs", Map.get(@codes, status, 0)}
           ])}
        ]

      [] ->
        []
    end
  end

  defp compact(pairs), do: Enum.reject(pairs, &is_nil(elem(&1, 1)))
end
