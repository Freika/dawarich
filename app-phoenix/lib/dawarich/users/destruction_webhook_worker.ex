defmodule Dawarich.Users.DestructionWebhookWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 0, max_attempts: 5
  alias Dawarich.AfterCommit.Callback
  alias Dawarich.Users.WebhookCommands

  def args_from_command(1, %{"user_id" => id, "email" => email} = payload)
      when map_size(payload) == 2 and is_integer(id) and
             id in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and is_binary(email),
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: trunc(Integer.pow(attempt, 4) * (1 + :rand.uniform() * 0.15) + 2)

  def run(repo, args, opts \\ []) do
    Callback.run(repo, args["event_id"], "users.destruction_webhook", fn ->
      if WebhookCommands.configured?(opts) do
        post(args, opts)
      else
        :ok
      end
    end)
  end

  defp post(args, opts) do
    payload = %{user_id: args["user_id"], email: args["email"], action: "destroy_user"}
    input = encode(~s({"alg":"HS256"})) <> "." <> encode(Jason.encode!(payload))
    key = Map.fetch!(WebhookCommands.env(opts), "JWT_SECRET_KEY")
    token = input <> "." <> encode(:crypto.mac(:hmac, :sha256, key, input))
    headers = [{"Content-Type", "application/json"}, {"Accept", "application/json"}]

    case Dawarich.Cloud.ProviderHTTP.post(
           :manager,
           "/api/v1/users/unlink",
           headers,
           Jason.encode!(%{token: token}),
           transport_options(opts)
         ) do
      {:ok, _status, _body} -> :ok
      {:error, _reason} -> {:error, :manager_transport}
    end
  end

  defp transport_options(opts) do
    http = Keyword.get(opts, :http, Application.get_env(:dawarich, :user_webhook_http))

    if http && !Keyword.has_key?(opts, :transport) do
      Keyword.put(opts, :transport, fn :post, origin, path, headers, body, false, timeout, _ ->
        case http.(origin <> path, headers, body, timeout) do
          {:ok, status, response} -> {:ok, status, [], response}
          {:error, reason} -> {:error, reason}
        end
      end)
    else
      opts
    end
  end

  defp encode(value), do: Base.url_encode64(value, padding: false)
end
