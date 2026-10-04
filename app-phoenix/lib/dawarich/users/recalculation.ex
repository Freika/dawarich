defmodule Dawarich.Users.Recalculation do
  @moduledoc false

  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.Stats.CalculateMonth
  alias Dawarich.Digests.Calculation
  alias Dawarich.Users.RecalculationPeriod, as: Period
  alias Dawarich.Users.RecalculationTracks

  def run(repo, oban, %{"user_id" => user_id} = args, opts \\ []) do
    case repo.query!("SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL", [user_id],
           log: false
         ).rows do
      [] ->
        {:ok, :skipped}

      [[settings]] ->
        with {:ok, years} <- Period.years(repo, user_id, args["year"]) do
          settings = if is_map(settings), do: settings, else: %{}

          state = %{
            user_id: user_id,
            years: years,
            settings: settings,
            locale: ExploreFeatures.locale(settings, nil),
            zone: Period.zone(repo, settings, env(opts))
          }

          if years == [],
            do: {:ok, :skipped},
            else: execute_with_fallback(repo, oban, args, state, opts)
        end
    end
  end

  defp execute_with_fallback(repo, oban, args, state, opts) do
    execute(repo, oban, args, state, opts)
  rescue
    ArgumentError ->
      execute(repo, oban, args, %{state | zone: Period.fallback_zone(repo, env(opts))}, opts)
  end

  defp execute(repo, oban, args, state, opts) do
    for year <- state.years, month <- 1..12 do
      Keyword.get(opts, :before_month, fn _, _, _ -> :ok end).(year, month, state)
      stats = Keyword.get(opts, :stats, &CalculateMonth.call/5)
      stats.(repo, state.user_id, year, month, stats_options(opts))
    end

    with :ok <- RecalculationTracks.run(repo, oban, state, args, opts) do
      for year <- state.years do
        Keyword.get(opts, :phase, fn _, _, _ -> :ok end).(:digest, year, state)

        options =
          Keyword.get(opts, :digest_opts, [])
          |> Keyword.merge(ambient_zone: state.zone, error_stack: true, env: env(opts))

        options = if opts[:now], do: Keyword.put(options, :now, opts[:now]), else: options

        case Calculation.yearly(repo, state.user_id, year, options) do
          {:ok, _} -> :ok
          {:error, error, stack} -> :erlang.raise(:error, error, stack)
        end
      end

      {:ok, state}
    end
  end

  defp stats_options(opts) do
    options = Keyword.get(opts, :stats_opts, [])

    case Keyword.get(opts, :now) do
      nil -> options
      %DateTime{} = now -> Keyword.put_new(options, :now, DateTime.to_naive(now))
      now -> Keyword.put_new(options, :now, now)
    end
  end

  defp env(opts), do: Keyword.get(opts, :env, System.get_env())
end
