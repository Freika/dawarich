defmodule Dawarich.Mail.Delivery do
  @moduledoc false
  require Logger

  @takeover_seconds 600

  @claim """
  INSERT INTO phoenix.delivery_claims AS c (handler, provider_key, event_id, claimed_at)
  VALUES ($1, $2, $3, $4)
  ON CONFLICT (handler, provider_key) DO UPDATE
    SET event_id = EXCLUDED.event_id, claimed_at = EXCLUDED.claimed_at
    WHERE c.delivered_at IS NULL
      AND (c.event_id = EXCLUDED.event_id
           OR c.claimed_at < EXCLUDED.claimed_at - make_interval(secs => #{@takeover_seconds}))
  RETURNING c.event_id
  """

  def claim(repo, handler, key, event_id, now \\ DateTime.utc_now()) do
    case repo.query!(@claim, [handler, key, Ecto.UUID.dump!(event_id), now], log: false).rows do
      [[_]] -> :send
      [] -> if delivered?(repo, handler, key), do: :delivered, else: :held
    end
  end

  def delivered!(repo, handler, key, event_id, now \\ DateTime.utc_now()) do
    repo.query!(
      "UPDATE phoenix.delivery_claims SET delivered_at = $4 WHERE handler = $1 AND provider_key = $2 AND event_id = $3",
      [handler, key, Ecto.UUID.dump!(event_id), now],
      log: false
    )

    :ok
  end

  def deliver(repo, handler, key, record, event_id, build) when is_function(build, 0) do
    case claim(repo, handler, key, event_id) do
      :delivered ->
        :ok

      :held ->
        {:snooze, @takeover_seconds}

      :send ->
        env = System.get_env()

        with {:ok, message} <- build.(),
             message = Map.put(message, :message_id, message_id(handler, key, record, env)),
             :ok <- transport().deliver(message, env) do
          delivered!(repo, handler, key, event_id)
        end
    end
  end

  def message_id(handler, key, record, env, secret \\ Dawarich.RailsSecret.fetch()) do
    mac = :crypto.mac(:hmac, :sha256, secret || "", Enum.join([handler, key, record], ":"))
    "<" <> Base.encode16(mac, case: :lower) <> "@" <> id_domain(env["DOMAIN"]) <> ">"
  end

  def warn_if_unkeyed(nil),
    do:
      Logger.warning(
        "SECRET_KEY_BASE could not be resolved; mail Message-IDs are keyed by the record alone"
      )

  def warn_if_unkeyed(_secret), do: :ok

  defp id_domain(domain) do
    case URI.parse("//" <> String.trim(domain || "")).host do
      host when host in [nil, ""] -> "dawarich.mail"
      host -> host
    end
  end

  defp delivered?(repo, handler, key) do
    repo.query!(
      "SELECT delivered_at IS NOT NULL FROM phoenix.delivery_claims WHERE handler = $1 AND provider_key = $2",
      [handler, key],
      log: false
    ).rows == [[true]]
  end

  defp transport, do: Application.get_env(:dawarich, :mail_transport, Dawarich.Mail.Smtp)
end
