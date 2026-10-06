defmodule Dawarich.Digests.WebCommands do
  @moduledoc false
  alias Dawarich.{Digests, Stats}
  alias Dawarich.Jobs.Ownership
  alias DawarichWeb.Translate

  def create(repo, user, raw_year, context) do
    if is_list(raw_year) or is_map(raw_year),
      do: raise(ArgumentError, "year does not support to_i")

    year = Digests.to_i(raw_year)
    scope = Stats.context(user, context.now, context.self_hosted)
    valid = year >= 1970 and year < scope.today.year and tracked?(repo, user.id, year, scope)

    if valid do
      repo.transaction(fn ->
        case if(Dawarich.Standalone.enabled?(),
               do: :oban,
               else: Ownership.lock(repo, "command:digests.calculate_year")
             ) do
          :oban ->
            repo.query!(
              "INSERT INTO public.job_outbox (event_id, command_type, command_version, payload, metadata, scheduled_at) VALUES (gen_random_uuid(), 'digests.calculate_year', 1, $1, $2, $3)",
              [
                %{"user_id" => user.id, "year" => year, "time_zone" => scope.zone},
                %{"producer" => "Users::DigestsController"},
                context.now
              ],
              log: false
            )

            result(context, "year_end_digest_for_year_is_being_generated_check_back", %{
              year: year
            })

          :sidekiq ->
            {:replay, "Sidekiq digest calculation"}
        end
      end)
      |> unwrap()
    else
      {:ok, result(context, "invalid_year_selected", %{}, :alert)}
    end
  end

  def destroy(repo, user, year, context) do
    repo.transaction(fn ->
      case repo.query!(
             "SELECT id, year FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1 LIMIT 1 FOR UPDATE",
             [user.id, Digests.to_i(year)],
             log: false
           ).rows do
        [[id, year]] ->
          repo.query!("DELETE FROM digests WHERE id=$1", [id], log: false)
          result(context, "year_end_digest_for_year_has_been_deleted", %{year: year})

        [] ->
          Map.put(result(context, "digest_not_found", %{}, :alert), :status, 302)
      end
    end)
    |> unwrap()
  end

  defp tracked?(repo, id, year, scope),
    do:
      Enum.any?(
        repo.query!("SELECT month FROM stats WHERE user_id=$1 AND year=$2", [id, year],
          log: false
        ).rows,
        fn [month] -> Stats.in_window?(%{year: year, month: month}, scope.cutoff) end
      )

  defp result(ctx, key, attrs, flash \\ :notice),
    do: %{
      status: 303,
      path: "/digests",
      flash: flash,
      message: Translate.t(ctx.locale, "controllers.users.digests." <> key, attrs)
    }

  defp unwrap({:ok, {:replay, _} = replay}), do: replay
  defp unwrap({:ok, result}), do: {:ok, result}
  defp unwrap({:error, reason}), do: {:error, reason}
end
