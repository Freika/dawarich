defmodule Dawarich.Digests.Run do
  @moduledoc false

  alias Dawarich.Digests.Calculation
  alias Dawarich.Stats.{Accounts, CalculateMonth}

  def monthly(repo, args, opts \\ []) do
    case Accounts.find(repo, args["user_id"]) do
      nil -> :missing
      _user -> calculate_month(repo, args, opts)
    end
  end

  def yearly(repo, args, opts \\ []) do
    case Accounts.find(repo, args["user_id"]) do
      nil -> :missing
      _user -> calculate_year(repo, args, opts)
    end
  end

  defp calculate_year(repo, args, opts) do
    stats = Keyword.get(opts, :stats, &CalculateMonth.call/5)

    for month <- 1..12 do
      stats.(repo, args["user_id"], args["year"], month, stats_options(opts))
    end

    yearly = Keyword.get(opts, :yearly, &Calculation.yearly/4)
    yearly.(repo, args["user_id"], args["year"], calculation_options(args, opts))
  rescue
    error -> {:error, error, __STACKTRACE__}
  catch
    kind, reason -> {:error, {kind, reason}, __STACKTRACE__}
  end

  defp calculate_month(repo, args, opts) do
    stats = Keyword.get(opts, :stats, &CalculateMonth.call/5)
    stats.(repo, args["user_id"], args["year"], args["month"], stats_options(opts))
    monthly = Keyword.get(opts, :monthly, &Calculation.monthly/5)
    monthly.(repo, args["user_id"], args["year"], args["month"], calculation_options(args, opts))
  rescue
    error -> {:error, error, __STACKTRACE__}
  catch
    kind, reason -> {:error, {kind, reason}, __STACKTRACE__}
  end

  defp calculation_options(args, opts),
    do: opts |> Keyword.put(:error_stack, true) |> Keyword.put(:ambient_zone, args["time_zone"])

  defp stats_options(opts) do
    options = Keyword.get(opts, :stats_opts, [])

    case Keyword.get(opts, :now) do
      nil -> options
      %DateTime{} = now -> Keyword.put_new(options, :now, DateTime.to_naive(now))
      now -> Keyword.put_new(options, :now, now)
    end
  end
end
