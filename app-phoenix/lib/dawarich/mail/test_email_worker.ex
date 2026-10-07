defmodule Dawarich.Mail.TestEmailWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, Recipient, Residual}
  alias Dawarich.{TimeZoneName, UserTimeZone}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => id, "locale" => locale} = args} = job) do
    case Recipient.fetch(Dawarich.Jobs.repo(), id) do
      nil ->
        :ok

      %{admin: true} = user ->
        env = System.get_env()
        event_id = event_id(job, args)

        Delivery.deliver(
          Dawarich.Jobs.repo(),
          "mail.test_email",
          event_id,
          NaiveDateTime.to_iso8601(user.created_at),
          event_id,
          fn ->
            {:ok,
             Residual.message(:test_email, user, locale, env,
               clock: clock(Dawarich.UserSettings.get(user), env)
             )}
          end
        )

      _ ->
        {:cancel, "admin required"}
    end
  end

  defp event_id(_job, %{"event_id" => event_id}), do: event_id

  defp event_id(%Oban.Job{id: id}, _args) when is_integer(id) and id > 0 do
    <<uuid::binary-size(16), _::binary>> = :crypto.hash(:sha256, "mail.test_email:#{id}")
    Ecto.UUID.load!(uuid)
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
