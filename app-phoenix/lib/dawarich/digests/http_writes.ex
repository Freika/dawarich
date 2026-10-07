defmodule Dawarich.Digests.HttpWrites do
  @moduledoc false
  alias Dawarich.{AfterCommit, Digests, I18n, Stats}

  def create(repo, user, raw_year, ctx) do
    if is_list(raw_year) or is_map(raw_year) or is_boolean(raw_year),
      do: raise(ArgumentError, "year does not support to_i")

    year = Digests.to_i(raw_year)
    scope = Stats.context(user, ctx.now, ctx.self_hosted?)

    cond do
      not valid?(repo, user.id, year, scope) ->
        error(422, "invalid_year")

      exists?(repo, user.id, year) ->
        error(409, "digest_already_exists")

      true ->
        AfterCommit.enqueue(repo, Dawarich.Digests.YearlyWorker, %{
          "event_id" => Ecto.UUID.generate(),
          "user_id" => user.id,
          "year" => year,
          "time_zone" => scope.zone
        })

        {:ok, 202,
         %{
           "message" =>
             DawarichWeb.Translate.t(
               "en",
               "controllers.api.v1.digests.digest_for_year_is_being_generated",
               %{year: year}
             )
         }}
    end
  end

  def destroy(repo, user, raw_year) do
    case repo.query!(
           "DELETE FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1 RETURNING id",
           [user.id, Digests.to_i(raw_year)],
           log: false
         ).rows do
      [] -> {:error, 404, %{"error" => I18n.en!("controllers.api.record_not_found")}}
      _ -> {:ok, 204, nil}
    end
  end

  defp valid?(repo, user, year, scope) do
    year >= 1970 and year < scope.today.year and
      Enum.any?(
        repo.query!("SELECT month FROM stats WHERE user_id=$1 AND year=$2", [user, year],
          log: false
        ).rows,
        fn [month] -> Stats.in_window?(%{year: year, month: month}, scope.cutoff) end
      )
  end

  defp exists?(repo, user, year),
    do:
      repo.query!(
        "SELECT 1 FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1 LIMIT 1",
        [user, year],
        log: false
      ).rows != []

  defp error(status, key),
    do: {:error, status, %{"error" => I18n.en!("controllers.api.v1.digests." <> key)}}
end
