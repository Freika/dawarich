defmodule Dawarich.Mail.ExploreFeaturesWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20
  alias Dawarich.Jobs.Processed
  alias Dawarich.Mail.{ExploreFeatures, Recipient}
  @handler "users.explore_features_mail"
  def args_from_command(1, %{"user_id" => user_id} = payload)
      when is_integer(user_id) and map_size(payload) == 1,
      do: {:ok, %{"user_id" => user_id, "locale" => nil}}

  def args_from_command(1, %{"user_id" => user_id, "locale" => locale} = payload)
      when is_integer(user_id) and (is_nil(locale) or is_binary(locale)) and
             map_size(payload) == 2,
      do: {:ok, %{"user_id" => user_id, "locale" => locale}}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_id" => event_id, "user_id" => user_id} = args}) do
    repo = Dawarich.Jobs.repo()

    with false <- Processed.done?(repo, event_id),
         %{} = recipient <- Recipient.fetch(repo, user_id),
         env = System.get_env(),
         :ok <- transport().deliver(ExploreFeatures.message(recipient, args["locale"], env), env),
         do: Processed.mark!(repo, event_id, @handler),
         else: (
           true -> :ok
           nil -> :ok
           {:error, reason} -> {:error, reason}
         )
  end

  defp transport, do: Application.get_env(:dawarich, :mail_transport, Dawarich.Mail.Smtp)
end
