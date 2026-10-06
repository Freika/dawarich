defmodule Dawarich.Mail.ResidualCommands do
  @moduledoc false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.RailsCommands

  def location(repo, payload) do
    select(
      repo,
      "mail.family_location_request",
      "family_location_request_mail",
      payload,
      payload,
      "location-request:#{payload["request_id"]}"
    )
  end

  def digest(repo, period, args) do
    monthly = period in ["month", "monthly"]
    period = if monthly, do: "monthly", else: "yearly"
    fields = if monthly, do: ~w(user_id year month time_zone), else: ~w(user_id year time_zone)
    payload = Map.take(args, fields)

    settings =
      case repo.query!("SELECT settings FROM public.users WHERE id=$1", [args["user_id"]],
             log: false
           ).rows do
        [[settings]] -> settings
        [] -> %{}
      end

    native = Map.put(payload, "locale", ExploreFeatures.locale(settings, "en"))
    reverse = if monthly, do: "digests.email_month", else: "digests.email_year"

    select(
      repo,
      "mail.digest." <> period,
      reverse,
      payload,
      native,
      "digest-mail:#{period}:#{args["event_id"]}"
    )
  end

  defp select(repo, type, reverse, rails, native, dedupe) do
    {:ok, :ok} =
      repo.transaction(fn ->
        owner =
          if Dawarich.Standalone.enabled?(),
            do: :oban,
            else: Ownership.lock(repo, "command:" <> type)

        case owner do
          :sidekiq ->
            RailsCommands.insert!(repo, reverse, rails)

          :oban ->
            repo.query!(
              "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING",
              [
                Ecto.UUID.dump!(Ecto.UUID.generate()),
                type,
                native,
                %{"producer" => "Phoenix residual mail"},
                native["user_id"],
                dedupe,
                DateTime.utc_now()
              ],
              log: false
            )
        end

        :ok
      end)

    :ok
  end
end
