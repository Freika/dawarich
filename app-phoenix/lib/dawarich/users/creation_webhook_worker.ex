defmodule Dawarich.Users.CreationWebhookWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 0, max_attempts: 26
  alias Dawarich.Jobs.Processed
  alias Dawarich.Users.WebhookCommands

  def args_from_command(1, %{"user_id" => id} = payload)
      when map_size(payload) == 1 and is_integer(id) and
             id in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, args, opts \\ []) do
    Processed.once(repo, args["event_id"], "users.creation_webhook", fn ->
      if WebhookCommands.configured?(opts), do: deliver(repo, args["user_id"], opts), else: :ok
    end)
  end

  defp deliver(repo, id, opts) do
    case repo.query!(
           "SELECT email,first_name,last_name,active_until,status FROM users WHERE id=$1 AND deleted_at IS NULL",
           [id],
           log: false
         ).rows do
      [[email, first, last, active, status]] ->
        payload = %{
          user_id: id,
          email: email,
          first_name: first,
          last_name: last,
          active_until: timestamp(active),
          status: %{0 => "inactive", 1 => "active", 2 => "trial", 3 => "pending_payment"}[status],
          action: "create_user"
        }

        WebhookCommands.post(payload, "/api/v1/users", nil, opts)

      [] ->
        :ok
    end
  end

  defp timestamp(nil), do: nil

  defp timestamp(%NaiveDateTime{} = at),
    do:
      at
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.truncate(:millisecond)
      |> DateTime.to_iso8601()
end
