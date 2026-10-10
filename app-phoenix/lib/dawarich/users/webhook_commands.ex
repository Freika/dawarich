defmodule Dawarich.Users.WebhookCommands do
  @moduledoc false
  alias Dawarich.AfterCommit

  def creation(repo, user, event \\ Ecto.UUID.generate(), opts \\ []),
    do: enqueue(repo, "users.creation_webhook", %{"user_id" => user}, event, opts)

  def destruction(repo, user, email, event \\ Ecto.UUID.generate()),
    do:
      enqueue(
        repo,
        "users.destruction_webhook",
        %{"user_id" => user, "email" => email},
        event,
        []
      )

  defp enqueue(repo, type, payload, event, opts) do
    case AfterCommit.intent(
           repo,
           type,
           payload,
           Keyword.merge(opts, event_id: event, aggregate_id: payload["user_id"])
         ) do
      {:error, :callback_owner} -> {:error, :webhook_owner}
      result -> result
    end
  end

  def configured?(opts), do: not blank?(env(opts)["MANAGER_URL"])

  def post(payload, path, timeout, opts) do
    env = env(opts)

    with :ok <- Dawarich.Cloud.Configuration.manager(env),
         do: signed_post(payload, path, timeout, Keyword.put(opts, :env, env))
  end

  defp signed_post(payload, path, timeout, opts) do
    env = env(opts)
    input = encode(~s({"alg":"HS256"})) <> "." <> encode(Jason.encode!(payload))

    token =
      input <>
        "." <> encode(:crypto.mac(:hmac, :sha256, Map.fetch!(env, "JWT_SECRET_KEY"), input))

    headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]

    opts =
      case Keyword.get(opts, :http, Application.get_env(:dawarich, :user_webhook_http)) do
        http when is_function(http, 4) ->
          Keyword.put(opts, :transport, fn _, origin, path, headers, body, _, _, _ ->
            case http.(origin <> path, headers, body, timeout) do
              {:ok, status, body} -> {:ok, status, [], body}
              error -> error
            end
          end)

        _ ->
          opts
      end

    case Dawarich.Cloud.ProviderHTTP.post(
           :manager,
           path,
           headers,
           Jason.encode!(%{token: token}),
           opts
         ) do
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
