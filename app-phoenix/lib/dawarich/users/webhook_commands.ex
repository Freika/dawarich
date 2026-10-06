defmodule Dawarich.Users.WebhookCommands do
  @moduledoc false
  alias Dawarich.Jobs.Ownership

  def creation(repo, user, event \\ Ecto.UUID.generate()),
    do: enqueue(repo, "users.creation_webhook", %{"user_id" => user}, event)

  def destruction(repo, user, email, event \\ Ecto.UUID.generate()),
    do: enqueue(repo, "users.destruction_webhook", %{"user_id" => user, "email" => email}, event)

  defp enqueue(repo, type, payload, event) do
    if repo.in_transaction?() do
      case Ownership.lock(repo, "command:" <> type) do
        :oban ->
          repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6) ON CONFLICT(event_id) DO NOTHING",
            [
              Ecto.UUID.dump!(event),
              type,
              payload,
              payload["user_id"],
              %{"producer" => "phoenix.users"},
              DateTime.utc_now()
            ],
            log: false
          )

          :ok

        _ ->
          {:error, :webhook_owner}
      end
    else
      {:error, :transaction_required}
    end
  end

  def configured?(opts), do: not blank?(env(opts)["MANAGER_URL"])

  def post(payload, path, timeout, opts) do
    env = env(opts)
    input = encode(~s({"alg":"HS256"})) <> "." <> encode(Jason.encode!(payload))

    token =
      input <>
        "." <> encode(:crypto.mac(:hmac, :sha256, Map.fetch!(env, "JWT_SECRET_KEY"), input))

    headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]

    http =
      Keyword.get(opts, :http, Application.get_env(:dawarich, :user_webhook_http, &request/4))

    case http.(env["MANAGER_URL"] <> path, headers, Jason.encode!(%{token: token}), timeout) do
      {:ok, _status, _body} -> :ok
      {:error, _reason} -> :manager_transport
    end
  end

  def request(url, headers, body, timeout) do
    request =
      {String.to_charlist(url),
       for({k, v} <- headers, do: {String.to_charlist(k), String.to_charlist(v)}),
       ~c"application/json", body}

    options = [ssl: Dawarich.Http.ssl_options()]

    options =
      if timeout, do: options ++ [timeout: timeout, connect_timeout: timeout], else: options

    case :httpc.request(:post, request, options, body_format: :binary) do
      {:ok, {{_, status, _}, _headers, response}} -> {:ok, status, response}
      {:error, reason} -> {:error, reason}
    end
  end

  def env(opts), do: Keyword.get_lazy(opts, :env, &System.get_env/0)
  def blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
  defp encode(value), do: Base.url_encode64(value, padding: false)
end
