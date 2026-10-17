defmodule Dawarich.Mail.DeviseNotificationWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, DeviseResidual, Recipient}
  @kinds %{"email_changed" => :email_changed, "password_change" => :password_change}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    repo = Dawarich.Jobs.repo()

    case Recipient.fetch(repo, args["user_id"]) do
      nil ->
        :ok

      user ->
        kind = Map.fetch!(@kinds, args["kind"])

        Delivery.deliver(
          repo,
          "mail.devise." <> args["kind"],
          args["event_id"],
          NaiveDateTime.to_iso8601(user.created_at),
          args["event_id"],
          fn ->
            {:ok,
             DeviseResidual.message(
               kind,
               args["recipient"],
               args["resource_email"],
               args["locale"],
               System.get_env()
             )}
          end
        )
    end
  end
end
