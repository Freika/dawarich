defmodule Dawarich.Partnero.CustomerSignupWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 0, max_attempts: 5
  alias Dawarich.AfterCommit.Callback
  alias Dawarich.Partnero.CustomerSignup

  def args_from_command(1, %{"user_id" => id, "partner_key" => partner} = payload)
      when map_size(payload) == 2 and is_integer(id) and
             id in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and
             (is_binary(partner) or is_nil(partner)),
      do: {:ok, payload}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: trunc(Integer.pow(attempt, 4) * (1 + :rand.uniform() * 0.15) + 2)

  def run(repo, args, opts \\ []) do
    Callback.run(repo, args["event_id"], "partnero.customer_signup", fn ->
      CustomerSignup.call(repo, args["user_id"], args["partner_key"], opts)
    end)
  end
end
