defmodule Dawarich.Users.DestructionWebhookWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 0, max_attempts: 5
  alias Dawarich.Jobs.Processed
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
    Processed.once(repo, args["event_id"], "users.destruction_webhook", fn ->
      if WebhookCommands.configured?(opts) do
        WebhookCommands.post(
          %{user_id: args["user_id"], email: args["email"], action: "destroy_user"},
          "/api/v1/users/unlink",
          10_000,
          opts
        )
      else
        :ok
      end
    end)
  end
end
