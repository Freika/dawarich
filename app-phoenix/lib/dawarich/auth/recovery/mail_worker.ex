defmodule Dawarich.Auth.Recovery.MailWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Auth.Recovery.{Mail, Notification}
  alias Dawarich.Mail.{Delivery, Recipient, SmtpConfig, Wave2}
  alias Dawarich.{RailsCookies, RailsSecret}

  @seal "dawarich.auth.recovery"
  @lifetime 6 * 3600
  @mirrored_envs ~w(production staging)
  @kinds %{
    "reset_password_instructions" => {:reset_password_instructions, "reset_password_token"},
    "unlock_instructions" => {:unlock_instructions, "unlock_token"}
  }

  def deliverable?(env) do
    env["RAILS_ENV"] in @mirrored_envs and present?(env["SMTP_FROM"]) and
      (present?(env["SMTP_SERVER"]) or present?(env["E2E_SMTP_PORT"])) and
      present?(env["DOMAIN"]) and base_url?(env) and transport?(env) and
      is_binary(RailsSecret.fetch())
  end

  def enqueue(%Notification{} = notification, oban \\ Oban, now \\ DateTime.utc_now()) do
    sealed =
      RailsCookies.encrypt(
        notification.raw,
        @seal,
        RailsSecret.fetch(),
        DateTime.add(now, @lifetime)
      )

    args = %{
      "event_id" => Ecto.UUID.generate(),
      "kind" => Atom.to_string(notification.kind),
      "user_id" => notification.user_id,
      "digest" => notification.digest,
      "locale" => notification.locale,
      "sealed" => sealed
    }

    case Oban.insert(oban, new(args)) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    {kind, column} = Map.fetch!(@kinds, args["kind"])
    repo = Dawarich.Jobs.repo()

    case RailsCookies.decrypt(args["sealed"], @seal, RailsSecret.fetch(), DateTime.utc_now()) do
      {:ok, raw} when is_binary(raw) ->
        if current?(repo, column, args["user_id"], args["digest"]),
          do: deliver(repo, kind, raw, args),
          else: :ok

      _ ->
        {:cancel, "recovery link expired"}
    end
  end

  defp deliver(repo, kind, raw, args) do
    env = System.get_env()

    with %{} = user <- Recipient.fetch(repo, args["user_id"]),
         {:ok, base_url} <- Wave2.base_url(env) do
      Delivery.deliver(
        repo,
        "mail.auth." <> args["kind"],
        "#{args["user_id"]}:#{args["digest"]}",
        NaiveDateTime.to_iso8601(user.created_at),
        args["event_id"],
        fn -> Mail.build(kind, user.email, args["locale"], raw, base_url, env) end
      )
    else
      nil -> :ok
      error -> error
    end
  end

  defp current?(repo, column, user_id, digest),
    do:
      repo.query!(
        "SELECT #{column} = $2 FROM users WHERE id = $1 AND deleted_at IS NULL",
        [user_id, digest],
        log: false
      ).rows == [[true]]

  defp base_url?(env) do
    case Wave2.base_url(env) do
      {:ok, base_url} -> Mail.valid_base_url?(base_url)
      _ -> false
    end
  end

  defp transport?(env) do
    SmtpConfig.options(env)
    true
  rescue
    ArgumentError -> false
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
