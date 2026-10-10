defmodule Dawarich.Mail.OtpAccountLockedWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, Recipient, Residual, Wave2}

  def enqueue(user) do
    args = %{"user_id" => user.id, "locale" => "en", "event_id" => Ecto.UUID.generate()}

    case Oban.insert(new(args)) do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    repo = Dawarich.Jobs.repo()

    case Recipient.fetch(repo, args["user_id"]) do
      nil ->
        :ok

      user ->
        with {:ok, base_url} <- Wave2.base_url(System.get_env()) do
          Delivery.deliver(
            repo,
            "mail.otp_account_locked",
            args["event_id"],
            NaiveDateTime.to_iso8601(user.created_at),
            args["event_id"],
            fn ->
              {:ok,
               Residual.message(:otp_account_locked, user, args["locale"], System.get_env(),
                 base_url: base_url
               )}
            end
          )
        end
    end
  end
end
