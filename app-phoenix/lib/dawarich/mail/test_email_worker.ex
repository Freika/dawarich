defmodule Dawarich.Mail.TestEmailWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Recipient, Residual}
  alias Dawarich.{TimeZoneName, UserTimeZone}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => id, "locale" => locale}}) do
    case Recipient.fetch(Dawarich.Jobs.repo(), id) do
      nil ->
        :ok

      user ->
        env = System.get_env()
        transport = Application.get_env(:dawarich, :mail_transport, Dawarich.Mail.Smtp)

        transport.deliver(
          Residual.message(:test_email, user, locale, env, clock: clock(user.settings, env)),
          env
        )
    end
  end

  defp clock(settings, env) do
    zone = UserTimeZone.zone(settings, env) |> TimeZoneName.to_iana()

    %{rows: [[local, offset, name, valid]]} =
      UserTimeZone.query!(
        "SELECT ($1::timestamptz AT TIME ZONE z.name)::timestamp, " <>
          "extract(epoch FROM (($1::timestamptz AT TIME ZONE z.name) - ($1::timestamptz AT TIME ZONE 'UTC')))::int, " <>
          "z.name, EXISTS(SELECT 1 FROM pg_timezone_names WHERE name = $2) FROM z",
        [DateTime.utc_now(), zone],
        settings,
        Dawarich.Jobs.repo(),
        env
      )

    %{local: local, offset: offset, zone: name, valid: valid}
  end
end
