defmodule Dawarich.Stats.WebCommands do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  alias DawarichWeb.{LocalizedDate, Translate}

  def update_all(repo, user, context) do
    repo.transaction(fn ->
      case Ownership.lock(repo, "command:stats.full_recalculation") do
        :oban ->
          if Dawarich.State.claim(repo, "stats_full_recalculation:user:#{user.id}", 900) do
            publish!(
              repo,
              "stats.full_recalculation",
              %{"user_id" => user.id, "source_job_id" => Ecto.UUID.generate()},
              context.now
            )
          end

          result(context, "stats_are_being_updated", %{})

        :sidekiq ->
          {:replay, "Sidekiq full stats recalculation"}
      end
    end)
    |> unwrap()
  end

  def update(repo, user, year, month, context) do
    if month == "all" or Regex.match?(~r/\A(?:0?[1-9]|1[0-2])\z/, month) do
      repo.transaction(fn ->
        case Ownership.lock(repo, "command:stats.calculate_month") do
          :oban ->
            for number <- if(month == "all", do: Enum.to_list(1..12), else: [month]) do
              publish!(
                repo,
                "stats.calculate_month",
                %{
                  "user_id" => user.id,
                  "year" => Dawarich.Digests.to_i(year),
                  "month" => Dawarich.Digests.to_i(number),
                  "notify_on_failure" => false
                },
                context.now
              )
            end

            target =
              if month == "all",
                do: t(context, "whole_year", %{year: year}),
                else:
                  t(context, "month_of_year", %{
                    year: year,
                    month:
                      LocalizedDate.month_name(
                        context.locale,
                        Dawarich.Digests.to_i(year),
                        Dawarich.Digests.to_i(month)
                      )
                  })

            result(context, "stats_for_target_are_being_updated", %{target: target})

          :sidekiq ->
            {:replay, "Sidekiq stats calculation"}
        end
      end)
      |> unwrap()
    else
      {:ok, result(context, "invalid_period", %{}, :alert)}
    end
  end

  defp publish!(repo, kind, payload, now) do
    repo.query!(
      "INSERT INTO public.job_outbox (event_id, command_type, command_version, payload, metadata, scheduled_at) VALUES (gen_random_uuid(), $1, 1, $2, $3, $4)",
      [kind, payload, %{"producer" => "StatsController"}, now],
      log: false
    )
  end

  defp result(context, key, attrs, flash \\ :notice),
    do: %{status: 303, path: "/stats", flash: flash, message: t(context, key, attrs)}

  defp t(context, key, attrs), do: Translate.t(context.locale, "controllers.stats." <> key, attrs)
  defp unwrap({:ok, {:replay, _} = replay}), do: replay
  defp unwrap({:ok, result}), do: {:ok, result}
  defp unwrap({:error, reason}), do: {:error, reason}
end
