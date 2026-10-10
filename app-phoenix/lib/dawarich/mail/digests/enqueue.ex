defmodule Dawarich.Mail.Digests.Enqueue do
  @moduledoc false

  alias Dawarich.Digests.Store
  alias Dawarich.Mail.Digests.Data
  alias Dawarich.{RubyInteger, UserSettings}

  def args(
        "monthly",
        1,
        %{
          "user_id" => id,
          "year" => year,
          "month" => month,
          "time_zone" => zone,
          "locale" => locale
        } = payload
      )
      when is_integer(id) and is_integer(year) and is_integer(month) and is_binary(zone) and
             is_binary(locale) and map_size(payload) == 5,
      do: {:ok, payload}

  def args(
        "yearly",
        1,
        %{"user_id" => id, "year" => year, "time_zone" => zone, "locale" => locale} = payload
      )
      when is_integer(id) and is_integer(year) and is_binary(zone) and is_binary(locale) and
             map_size(payload) == 4,
      do: {:ok, payload}

  def args(_, 1, _), do: {:error, "invalid_payload"}
  def args(_, _, _), do: {:error, "unsupported_version"}

  def run(repo, period, args, opts \\ []) do
    records = Data.load(repo, args["user_id"], period, args["year"], args["month"])

    if eligible?(records, period) do
      %{user: user, digest: digest} = records

      delivery =
        Map.take(args, ~w(user_id event_id time_zone locale))
        |> Map.put("digest_id", digest["id"])

      job =
        Oban.Job.new(delivery,
          worker: "Dawarich.Mail.Digests.DeliveryWorker",
          queue: :mailers,
          max_attempts: 20
        )

      Oban.insert!(Keyword.get(opts, :oban, Oban), job)
      if callback = Keyword.get(opts, :after_enqueue), do: callback.()
      Store.mark_sent!(repo, user.id, digest, Keyword.get_lazy(opts, :now, &DateTime.utc_now/0))
    end

    :ok
  rescue
    _error -> {:error, "digest_mail_enqueue_failed"}
  end

  defp eligible?(nil, _), do: false

  defp eligible?(%{user: user, digest: digest}, period) do
    is_nil(user.deleted_at) and UserSettings.digest?(user, period <> "_digest_emails_enabled") and
      is_nil(digest["sent_at"]) and RubyInteger.to_i(digest["distance"]) != 0
  end
end
