defmodule Dawarich.AirTrail.StatsFollowUp do
  @moduledoc false
  alias Dawarich.Stats.{Accounts, Schedule}

  def call(repo, payload, opts \\ []) do
    case Accounts.find(repo, payload["user_id"]) do
      nil ->
        :ok

      user ->
        months = payload["months"] ++ epochs(repo, payload["departure_epochs"], user.zone)

        current =
          repo.query!(
            "SELECT DISTINCT extract(year FROM COALESCE(flight_date, departure_time AT TIME ZONE 'UTC' AT TIME ZONE $2))::integer, extract(month FROM COALESCE(flight_date, departure_time AT TIME ZONE 'UTC' AT TIME ZONE $2))::integer FROM flights WHERE user_id=$1 AND (flight_date IS NOT NULL OR departure_time IS NOT NULL)",
            [user.id, user.zone],
            log: false
          ).rows

        for [year, month] <- Enum.uniq(months ++ current) do
          Schedule.calculate(repo, user.id, year, month, true, opts)
        end

        :ok
    end
  end

  defp epochs(_repo, [], _zone), do: []

  defp epochs(repo, epochs, zone) do
    repo.query!(
      "SELECT DISTINCT extract(year FROM to_timestamp(e) AT TIME ZONE $2)::integer, extract(month FROM to_timestamp(e) AT TIME ZONE $2)::integer FROM unnest($1::bigint[]) e",
      [epochs, zone],
      log: false
    ).rows
  end
end
