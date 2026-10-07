defmodule Dawarich.Partnero.CustomerSignup do
  @moduledoc false
  alias Dawarich.AfterCommit
  alias Dawarich.Users.WebhookCommands

  def enqueue(repo, user, partner, event \\ nil) do
    event = event || AfterCommit.identity(user, "partnero.customer_signup")

    case AfterCommit.intent(
           repo,
           "partnero.customer_signup",
           %{"user_id" => user, "partner_key" => partner},
           event_id: event,
           dedupe_key: event,
           aggregate_id: user
         ) do
      {:error, :callback_owner} -> {:error, :partnero_owner}
      result -> result
    end
  end

  def call(repo, user, partner, opts \\ []) do
    if repo.in_transaction?(),
      do: {:error, :transaction_required},
      else: deliver(repo, user, partner, opts)
  end

  defp deliver(repo, user, partner, opts) do
    env = WebhookCommands.env(opts)

    if WebhookCommands.blank?(env["PARTNERO_API_KEY"]) or WebhookCommands.blank?(partner) do
      :ok
    else
      case repo.query!(
             "SELECT email,first_name,last_name FROM users WHERE id=$1 AND deleted_at IS NULL",
             [user],
             log: false
           ).rows do
        [[email, first, last]] ->
          payload = %{
            partner: %{key: partner},
            key: Integer.to_string(user),
            email: email,
            name: first,
            surname: last
          }

          headers = [
            {"Authorization", "Bearer " <> env["PARTNERO_API_KEY"]},
            {"Content-Type", "application/json"},
            {"Accept", "application/json"}
          ]

          Dawarich.Cloud.ProviderHTTP.post(
            :partnero,
            "/v1/customers",
            headers,
            Jason.encode!(payload),
            transport_options(opts)
          )
          |> response()

        [] ->
          :ok
      end
    end
  end

  defp transport_options(opts) do
    legacy = Keyword.get(opts, :http, Application.get_env(:dawarich, :partnero_http))

    if not Keyword.has_key?(opts, :transport) and is_function(legacy, 4) do
      transport = fn :post, origin, path, headers, body, false, timeout, _opts ->
        case legacy.(origin <> path, headers, body, timeout) do
          {:ok, status, response} -> {:ok, status, [], response}
          {:error, _} = error -> error
        end
      end

      Keyword.put(opts, :transport, transport)
    else
      opts
    end
  end

  defp response({:ok, status, _body}) when status in 200..299 or status == 409, do: :ok
  defp response({:ok, status, _body}), do: {:error, {:partnero_status, status}}
  defp response({:error, _reason}), do: {:error, :partnero_transport}
end
