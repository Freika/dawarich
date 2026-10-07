defmodule Dawarich.Stats.Accounts do
  @moduledoc false

  alias Dawarich.{RubyInteger, UserTimeZone}
  alias Dawarich.Trips.Calculation

  @select "SELECT id, settings, stats_swept_at FROM users WHERE deleted_at IS NULL AND id"

  def find(repo, id), do: one(repo, @select <> " = $1", id)
  def first_from(repo, id), do: one(repo, @select <> " >= $1 ORDER BY id LIMIT 1", id)

  defp one(repo, sql, id) do
    case repo.query!(sql, [id], log: false).rows do
      [[id, settings, swept_at]] ->
        account(repo, id, Dawarich.UserSettings.safe(settings), swept_at)

      [] ->
        nil
    end
  end

  defp account(repo, id, settings, swept_at) do
    %{
      id: id,
      settings: settings,
      swept_at: swept_at,
      zone: UserTimeZone.iana(repo, settings),
      min_minutes: RubyInteger.to_i(Map.get(settings, "min_minutes_spent_in_city") || 60),
      gap_seconds: Calculation.minutes_between_routes(settings) * 60
    }
  end
end
