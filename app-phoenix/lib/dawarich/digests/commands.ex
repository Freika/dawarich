defmodule Dawarich.Digests.Commands do
  @moduledoc false
  alias Dawarich.{Repo, State, Stats}
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.Analytics.Period

  def generate(subject, params, receipt, opts \\ []) do
    with {:ok, receipt} <- Ecto.UUID.cast(receipt) do
      transact(subject, params, opts, fn scope, period ->
        if not active?(scope.user, period.now), do: Repo.rollback(:inactive)

        if period.year < 1970 or period.year >= period.today.year,
          do: Repo.rollback(:invalid_input)

        tracked =
          Repo.query!(
            "SELECT month FROM stats WHERE user_id=$1 AND year=$2",
            [scope.user.id, period.year],
            log: false
          ).rows

        if not Enum.any?(tracked, fn [month] ->
             Stats.in_window?(%{year: period.year, month: month}, period.cutoff)
           end),
           do: Repo.rollback(:invalid_input)

        key = "native-digest-generation:#{scope.user.id}:#{receipt}:#{period.year}"

        if State.claim_persistent_all(Repo, [key]) != [] do
          Repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,scheduled_at) VALUES($1,'digests.calculate_year',1,$2,$3,$4)",
            [
              Ecto.UUID.dump!(
                Dawarich.Stats.EffectIdentity.id(receipt, "native-digest-generation", %{
                  "user_id" => scope.user.id,
                  "year" => period.year
                })
              ),
              %{"user_id" => scope.user.id, "year" => period.year, "time_zone" => period.zone},
              %{"producer" => "Users::DigestsController"},
              period.now
            ],
            log: false
          )
        end

        %{year: period.year, notice: "year_end_digest_for_year_is_being_generated_check_back"}
      end)
    else
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def delete(subject, params, opts \\ []) do
    transact(subject, params, opts, fn scope, period ->
      case Repo.query!(
             "SELECT id FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1 LIMIT 1 FOR UPDATE",
             [scope.user.id, period.year],
             log: false
           ).rows do
        [[id]] ->
          Repo.query!("DELETE FROM digests WHERE id=$1", [id], log: false)
          %{year: period.year, notice: "year_end_digest_for_year_has_been_deleted"}

        [] ->
          Repo.rollback(:not_found)
      end
    end)
  rescue
    _ -> {:error, :unavailable}
  end

  def share(subject, params, attrs, opts \\ []) do
    if is_map(attrs) and attrs["enabled"] in ["0", "1"] and attrs["expiration"] in ~w(1h 12h 24h) do
      transact(subject, params, opts, fn scope, period ->
        if not active?(scope.user, period.now), do: Repo.rollback(:inactive)

        case Dawarich.Sharing.change_report(
               scope,
               %{type: :digest, owner_id: scope.user.id, year: period.year},
               attrs,
               opts
             ) do
          {:ok, result} -> result
          :not_found -> Repo.rollback(:not_found)
          _ -> Repo.rollback(:unavailable)
        end
      end)
    else
      {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp transact(subject, params, opts, operation) do
    with {:ok, scope} <- DataAccess.admit(subject, settings: true) do
      Dawarich.Transaction.run(Repo, fn ->
        Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [scope.user.id], log: false)

        case Period.admit(subject, params, :digest, opts) do
          {:ok, fresh, period} -> operation.(fresh, period)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def active?(%{active_until: %DateTime{} = until}, now),
    do: DateTime.compare(until, now) == :gt

  def active?(%{active_until: %NaiveDateTime{} = until}, now),
    do: NaiveDateTime.compare(until, DateTime.to_naive(now)) == :gt

  def active?(_, _), do: false
end
