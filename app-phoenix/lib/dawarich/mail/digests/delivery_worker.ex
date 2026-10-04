defmodule Dawarich.Mail.Digests.DeliveryWorker do
  @moduledoc false
  use Oban.Worker, queue: :mailers, max_attempts: 20

  alias Dawarich.Mail.{Delivery, Wave2}
  alias Dawarich.Mail.Digests.{Data, Render}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  def provider_key(args), do: "#{args["digest_id"]}:#{args["event_id"]}"

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "user_id" => user,
            "digest_id" => digest,
            "event_id" => event,
            "time_zone" => zone,
            "locale" => locale
          } = args
      })
      when is_integer(user) and is_integer(digest) and is_binary(event) and is_binary(zone) and
             is_binary(locale) and map_size(args) == 5 do
    repo = Dawarich.Jobs.repo()

    case Data.delivery(repo, user, digest) do
      nil -> :ok
      records -> deliver(repo, args, records)
    end
  rescue
    _error -> {:error, "digest_mail_delivery_failed"}
  end

  def perform(_), do: {:error, "invalid_payload"}

  defp deliver(repo, args, %{user: user, digest: digest}) do
    env = System.get_env()

    with {:ok, base_url} <- Wave2.base_url(env) do
      Delivery.deliver(
        repo,
        "mail.digest",
        provider_key(args),
        to_string(digest["id"]),
        args["event_id"],
        fn ->
          {:ok, Render.message(repo, user, digest, args["locale"], env, base_url)}
        end
      )
    end
    |> case do
      {:error, _} -> {:error, "digest_mail_delivery_failed"}
      result -> result
    end
  end
end
