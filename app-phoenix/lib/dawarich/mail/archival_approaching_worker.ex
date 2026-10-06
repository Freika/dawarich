defmodule Dawarich.Mail.ArchivalApproachingWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, Wave2}

  @handler "mail.user.archival_approaching"
  @payload %{"user_id" => :integer, "locale" => :string, "epoch" => :string}

  def args_from_command(version, payload), do: Wave2.decode(version, payload, @payload)

  def provider_key(%{"user_id" => user_id, "epoch" => epoch}),
    do: "archival-approaching:#{user_id}:#{epoch}"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    repo = Dawarich.Jobs.repo()
    key = provider_key(args)

    Wave2.deliver_to_user(repo, @handler, key, args, fn user, locale, env ->
      issued_at = Delivery.issued_at(repo, @handler, key)
      record = NaiveDateTime.to_iso8601(user.created_at)

      jti =
        Delivery.message_id(@handler, key, record, env)
        |> String.slice(1, 32)
        |> Base.decode16!(case: :lower)
        |> Ecto.UUID.load!()

      Wave2.archival_approaching(user_id, user, locale, env, issued_at, jti)
    end)
  end
end
