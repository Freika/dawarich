defmodule Dawarich.Stats.Commands do
  @moduledoc false
  alias Dawarich.{Repo, State}
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Analytics.Period

  def update(subject, params, receipt, opts \\ []) do
    with {:ok, receipt} <- Ecto.UUID.cast(receipt),
         {:ok, scope, period} <- Period.admit(subject, params || %{}, :year, opts) do
      transact(subject, opts, fn fresh ->
        selection =
          if is_nil(params),
            do: "all",
            else: "#{period.year}:#{if(params["month"] == "all", do: "all", else: period.month)}"

        key = "native-stats-command:#{fresh.user.id}:#{receipt}:#{selection}"

        if State.claim_persistent_all(Repo, [key]) != [] do
          if is_nil(params) do
            if State.claim(Repo, "stats_full_recalculation:user:#{fresh.user.id}", 300) do
              Dawarich.Stats.StatsFullRecalculationEffects.call(Repo, %{
                "user_id" => fresh.user.id,
                "source_job_id" => receipt,
                "run_at" => DateTime.to_unix(period.now, :microsecond) / 1_000_000
              })
            end
          else
            if params["month"] != "all" and
                 not Regex.match?(~r/\A(?:0?[1-9]|1[0-2])\z/, params["month"] || ""),
               do: Repo.rollback(:invalid_input)

            months = if params["month"] == "all", do: Enum.to_list(1..12), else: [period.month]
            if not Enum.all?(months, &(&1 in 1..12)), do: Repo.rollback(:invalid_input)

            for month <- months do
              event =
                Dawarich.Stats.EffectIdentity.id(receipt, "native-stats-calculate", %{
                  "user_id" => scope.user.id,
                  "year" => period.year,
                  "month" => month
                })

              Oban.insert!(
                Dawarich.Stats.CalculateMonthWorker.new(%{
                  "user_id" => fresh.user.id,
                  "year" => period.year,
                  "month" => month,
                  "notify_on_failure" => true,
                  "execution_receipt" => event,
                  "event_id" => event
                })
              )
            end
          end
        end

        %{
          notice: if(is_nil(params), do: :all, else: :period),
          year: period.year,
          month: params && params["month"]
        }
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def sharing(subject, params, opts \\ []) do
    with {:ok, scope, period} <- Period.admit(subject, params, :month, opts),
         {:ok, scope} <- DataAccess.admit(scope, Keyword.put(opts, :full_access, true)) do
      Dawarich.Sharing.report_controls(
        scope,
        %{type: :month, owner_id: scope.user.id, year: period.year, month: period.month},
        opts
      )
    end
  end

  def share(subject, params, attrs, opts \\ []) do
    with true <-
           is_map(attrs) and attrs["enabled"] in ["0", "1"] and
             attrs["expiration"] in ~w(1h 12h 24h),
         {:ok, _, period} <- Period.admit(subject, params, :month, opts) do
      transact(subject, Keyword.put(opts, :full_access, true), fn fresh ->
        case Dawarich.Sharing.change_report(
               fresh,
               %{type: :month, owner_id: fresh.user.id, year: period.year, month: period.month},
               attrs,
               opts
             ) do
          {:ok, result} -> result
          :not_found -> Repo.rollback(:not_found)
          _ -> Repo.rollback(:unavailable)
        end
      end)
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_input}
    end
  end

  defp transact(subject, opts, operation) do
    with {:ok, scope} <- DataAccess.admit(subject, settings: true) do
      Dawarich.Transaction.run(Repo, fn ->
        Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [scope.user.id], log: false)

        with {:ok, fresh} <- DataAccess.admit(subject, Keyword.merge(opts, settings: true)),
             true <- active?(fresh.user, Keyword.get(opts, :now, DateTime.utc_now())) do
          operation.(fresh)
        else
          {:error, reason} -> Repo.rollback(reason)
          _ -> Repo.rollback(:unauthorized)
        end
      end)
    end
  end

  defp active?(%{active_until: %DateTime{} = until}, now), do: DateTime.compare(until, now) == :gt

  defp active?(%{active_until: %NaiveDateTime{} = until}, now),
    do: NaiveDateTime.compare(until, DateTime.to_naive(now)) == :gt

  defp active?(_, _), do: false
end
