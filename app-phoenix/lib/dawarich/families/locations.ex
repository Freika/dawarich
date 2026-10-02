defmodule Dawarich.Families.Locations do
  @moduledoc false

  alias Dawarich.{I18n, RailsTime, Repo}
  alias Dawarich.Families.Sharing

  @statuses ~w(unknown unplugged charging full connected_not_charging discharging)

  def read(user, now) do
    case membership(user.id) do
      [_settings, nil] ->
        {:ok, 404, not_in_family()}

      [settings, family_id] ->
        sharing =
          for member <- members(family_id), Sharing.enabled?(member.settings, now), do: member

        own = Sharing.enabled?(settings, now)

        RailsTime.with_zone(user.timezone, fn ->
          {:ok, 200,
           {:object,
            [
              {"locations", Enum.flat_map(sharing, &location/1)},
              {"updated_at", stamp(now)},
              {"sharing_enabled", own}
            ]}}
        end)
    end
  end

  def not_in_family,
    do:
      {:object,
       [{"error", I18n.en!("controllers.api.v1.families.locations.user_is_not_part_of_a_family")}]}

  def membership(user_id) do
    [row] =
      Repo.query!(
        "SELECT u.settings, m.family_id FROM users u " <>
          "LEFT JOIN family_memberships m ON m.user_id = u.id WHERE u.id = $1",
        [user_id]
      ).rows

    row
  end

  def members(family_id) do
    Repo.query!(
      "SELECT u.id, u.email, u.settings FROM users u " <>
        "INNER JOIN family_memberships m ON u.id = m.user_id " <>
        "WHERE u.deleted_at IS NULL AND m.family_id = $1",
      [family_id]
    ).rows
    |> Enum.map(fn [id, email, settings] -> %{id: id, email: email, settings: settings} end)
  end

  defp location(member) do
    case Repo.query!(latest_sql(), [member.id]).rows do
      [] ->
        []

      [[lat, lon, timestamp, battery, status, updated_at]] ->
        [
          {:object,
           [
             {"user_id", member.id},
             {"email", member.email},
             {"email_initial", initial(member.email)},
             {"latitude", lat},
             {"longitude", lon},
             {"timestamp", timestamp},
             {"updated_at", updated_at},
             {"battery", battery},
             {"battery_status", status(status)}
           ]}
        ]
    end
  end

  def initial(email) do
    case String.next_codepoint(email) do
      {first, _rest} -> String.upcase(first)
      nil -> ""
    end
  end

  defp status(code) when is_integer(code) and code in 0..5, do: Enum.at(@statuses, code)
  defp status(_code), do: nil

  defp stamp(now) do
    [[text]] =
      Repo.query!("SELECT " <> RailsTime.sql("$1::timestamp", 0), [DateTime.to_naive(now)]).rows

    text
  end

  defp latest_sql do
    """
    SELECT ST_Y(p.lonlat::geometry), ST_X(p.lonlat::geometry), p.timestamp, p.battery,
           CASE WHEN p.source_id IS NULL THEN p.battery_status ELSE s.battery_status END,
           #{RailsTime.sql("(to_timestamp(p.timestamp) AT TIME ZONE 'UTC')", 3)}
    FROM points p LEFT JOIN point_sources s ON s.id = p.source_id
    WHERE p.user_id = $1 AND p.timestamp IS NOT NULL AND p.lonlat IS NOT NULL
      AND (p.anomaly = false OR p.anomaly IS NULL)
    ORDER BY p.timestamp DESC LIMIT 1
    """
  end
end
