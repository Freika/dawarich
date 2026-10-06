defmodule Dawarich.Partnero.CustomerSignup do
  @moduledoc false
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Users.WebhookCommands

  def enqueue(repo, user, partner, event \\ Ecto.UUID.generate()) do
    if repo.in_transaction?() do
      case Ownership.lock(repo, "command:partnero.customer_signup") do
        :oban ->
          repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,'partnero.customer_signup',1,$2,$3,$4,$5) ON CONFLICT(event_id) DO NOTHING",
            [
              Ecto.UUID.dump!(event),
              %{"user_id" => user, "partner_key" => partner},
              user,
              %{"producer" => "phoenix.partnero"},
              DateTime.utc_now()
            ],
            log: false
          )

          :ok

        _ ->
          {:error, :partnero_owner}
      end
    else
      {:error, :transaction_required}
    end
  end

  def call(repo, user, partner, opts \\ []) do
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

          http =
            Keyword.get(
              opts,
              :http,
              Application.get_env(:dawarich, :partnero_http, &WebhookCommands.request/4)
            )

          response(
            http.(
              "https://api.partnero.com/v1/customers",
              headers,
              Jason.encode!(payload),
              10_000
            )
          )

        [] ->
          :ok
      end
    end
  end

  defp response({:ok, status, _body}) when status in 200..299 or status == 409, do: :ok
  defp response({:ok, status, _body}), do: {:partnero_status, status}
  defp response({:error, _reason}), do: :partnero_transport
end
