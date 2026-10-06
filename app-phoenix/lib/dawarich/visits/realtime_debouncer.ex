defmodule Dawarich.Visits.RealtimeDebouncer do
  @moduledoc false

  require Logger

  alias Dawarich.{Entitlements, RailsCommands, State, UserTimeZone}
  alias Dawarich.Geocoding.Config
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Visits.Settings

  @delay 300
  @ttl 600
  @lookback 21_600

  def trigger(repo, user_id, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    {:ok, _} =
      repo.transaction(fn ->
        native =
          Dawarich.Standalone.enabled?(env) or
            Ownership.lock(repo, "command:visits.suggest") == :oban

        if native,
          do: schedule(repo, user_id, env, opts),
          else: RailsCommands.insert!(repo, "visits.realtime", %{"user_id" => user_id})
      end)

    :ok
  end

  def clear(repo, user_id) do
    State.unclaim(repo, key(user_id))
  rescue
    exception in [DBConnection.ConnectionError, Postgrex.Error] ->
      Logger.warning(
        "event=visits.debounce_release_failed user_id=#{user_id} error=#{Exception.message(exception)}"
      )

      :ok
  end

  defp schedule(repo, user_id, env, opts) do
    with true <- Config.resolve(repo, env).enabled,
         %{settings: settings} <- Settings.load(repo, user_id),
         true <- Settings.policy(settings).suggestions_enabled,
         true <- State.debounce(repo, key(user_id), @ttl) do
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      [[plan]] = repo.query!("SELECT plan FROM users WHERE id=$1", [user_id], log: false).rows

      payload = %{
        "user_id" => user_id,
        "start_at" => DateTime.to_unix(now) - @lookback,
        "end_at" => DateTime.to_unix(now),
        "stepping" => "calendar",
        "time_zone" => UserTimeZone.iana(repo, settings, env),
        "plan_restricted" =>
          not Entitlements.full_access?(
            repo,
            %{id: user_id, plan: plan},
            DawarichWeb.LayoutAssigns.self_hosted?(env),
            now
          )
      }

      repo.query!(
        "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,'visits.suggest',1,$2,$3,$4,$5)",
        [
          Ecto.UUID.bingenerate(),
          payload,
          %{"producer" => "Visits::RealtimeDebouncer"},
          user_id,
          DateTime.add(now, @delay)
        ],
        log: false
      )
    end

    :ok
  end

  defp key(user_id), do: "visit_realtime:user:#{user_id}"
end
