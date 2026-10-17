defmodule Dawarich.Mail.WelcomeWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.Wave2

  @handler "mail.user.welcome"
  @payload %{"user_id" => :integer, "locale" => :string}

  def args_from_command(version, payload), do: Wave2.decode(version, payload, @payload)

  def provider_key(%{"user_id" => user_id}), do: "welcome:#{user_id}"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}),
    do:
      Wave2.deliver_to_user(
        Dawarich.Jobs.repo(),
        @handler,
        provider_key(args),
        args,
        &Wave2.welcome/3
      )
end
