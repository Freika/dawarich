defmodule Dawarich.Mail.ArchivalApproachingWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.Wave2

  @handler "mail.user.archival_approaching"
  @payload %{"user_id" => :integer, "locale" => :string, "epoch" => :string}

  def args_from_command(version, payload), do: Wave2.decode(version, payload, @payload)

  def provider_key(%{"user_id" => user_id, "epoch" => epoch}),
    do: "archival-approaching:#{user_id}:#{epoch}"

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id} = args}) do
    Wave2.deliver_to_user(Dawarich.Jobs.repo(), @handler, provider_key(args), args, fn user,
                                                                                       locale,
                                                                                       env ->
      Wave2.archival_approaching(user_id, user, locale, env)
    end)
  end
end
