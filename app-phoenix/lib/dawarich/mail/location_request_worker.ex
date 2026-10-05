defmodule Dawarich.Mail.LocationRequestWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, Residual, Wave2}

  def args_from_command(1, %{"request_id" => request, "user_id" => user} = payload)
      when is_integer(request) and is_integer(user) and map_size(payload) == 2,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  def provider_key(args), do: "location-request:#{args["request_id"]}"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    repo = Dawarich.Jobs.repo()

    case repo.query!(
           "SELECT r.created_at, q.email, t.email, t.settings FROM public.family_location_requests r " <>
             "JOIN public.users q ON q.id=r.requester_id AND q.deleted_at IS NULL " <>
             "LEFT JOIN public.users t ON t.id=r.target_user_id AND t.deleted_at IS NULL WHERE r.id=$1 AND r.requester_id=$2",
           [args["request_id"], args["user_id"]],
           log: false
         ).rows do
      [] ->
        :ok

      [[_, _, nil, _]] ->
        {:error, "location_mail_recipient_missing"}

      [[created, requester, email, settings]] ->
        deliver(repo, args, created, requester, %{email: email, settings: settings})
    end
  rescue
    _error -> {:error, "location_mail_delivery_failed"}
  end

  defp deliver(repo, args, created, requester, target) do
    env = System.get_env()

    with {:ok, base_url} <- Wave2.base_url(env) do
      Delivery.deliver(
        repo,
        "mail.location_request",
        provider_key(args),
        NaiveDateTime.to_iso8601(created),
        args["event_id"],
        fn ->
          {:ok,
           Residual.message(:location_request, target, "en", env,
             base_url: base_url,
             requester: requester,
             request_id: args["request_id"]
           )}
        end
      )
    end
    |> case do
      {:error, _} -> {:error, "location_mail_delivery_failed"}
      result -> result
    end
  end
end
