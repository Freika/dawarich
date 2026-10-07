defmodule Dawarich.Digests.Sharing do
  @moduledoc false
  alias Dawarich.{Accounts, Digests, Repo, UserTimeZone}
  alias DawarichWeb.Translate

  def update(repo, user, year, attrs, context) do
    repo.transaction(fn ->
      case repo.query!(
             "SELECT id, month, sharing_uuid::text FROM digests WHERE user_id=$1 AND year=$2 AND period_type=1 LIMIT 1 FOR UPDATE",
             [user.id, Digests.to_i(year)],
             log: false
           ).rows do
        [[id, month, uuid]] ->
          if month != nil and month not in 1..12, do: raise(ArgumentError, "invalid month")
          settings = settings(repo, Dawarich.UserSettings.get(user), attrs, context.now)
          uuid = uuid || Ecto.UUID.generate()

          repo.query!(
            "UPDATE digests SET sharing_settings=$2, sharing_uuid=$3, updated_at=$4 WHERE id=$1",
            [id, settings, Ecto.UUID.dump!(uuid), DateTime.to_naive(context.now)],
            log: false
          )

          response(uuid, settings, context, "digests", "digest")

        [] ->
          :not_found
      end
    end)
    |> unwrap()
  end

  def settings(repo, settings, attrs, now) do
    if attrs["enabled"] == "1" do
      expiration =
        if attrs["expiration"] in ~w(1h 12h 24h 1w 1m), do: attrs["expiration"], else: "24h"

      interval =
        %{
          "1h" => "1 hour",
          "12h" => "12 hours",
          "24h" => "24 hours",
          "1w" => "7 days",
          "1m" => "1 month"
        }[expiration]

      zone = UserTimeZone.name(settings, repo)

      due =
        if String.ends_with?(expiration, "h"),
          do: "$1::timestamptz + $2::text::interval",
          else: "(($1::timestamptz AT TIME ZONE $3) + $2::text::interval) AT TIME ZONE $3"

      [[wall, seconds]] =
        repo.query!(
          "SELECT due AT TIME ZONE $3, extract(epoch FROM ((due AT TIME ZONE $3) - (due AT TIME ZONE 'UTC')))::integer FROM (SELECT #{due} AS due) x",
          [now, interval, zone],
          log: false
        ).rows

      offset = Dawarich.LocalTime.offset(zone, seconds, :iso)

      text =
        NaiveDateTime.to_iso8601(NaiveDateTime.truncate(wall, :second)) <>
          if(offset == "Z", do: "+00:00", else: offset)

      %{"enabled" => true, "expiration" => expiration, "expires_at" => text}
    else
      %{"enabled" => false, "expiration" => nil, "expires_at" => nil}
    end
  end

  def response(uuid, settings, context, scope, kind) do
    url = if settings["enabled"], do: context.base_url <> "/shared/#{kind}/#{uuid}", else: ""
    key = if settings["enabled"], do: "sharing_enabled", else: "sharing_disabled"

    %{
      uuid: uuid,
      settings: settings,
      body: %{
        "success" => true,
        "sharing_url" => url,
        "message" => Translate.t(context.locale, "controllers.shared.#{scope}.#{key}", %{})
      }
    }
  end

  def public?(%{"enabled" => true} = settings, now) do
    if settings["expiration"] in [nil, "", false] do
      true
    else
      with raw when is_binary(raw) <- settings["expires_at"],
           {:ok, at, _} <- DateTime.from_iso8601(raw),
           do: DateTime.compare(now, at) != :gt,
           else: (_ -> false)
    end
  end

  def public?(_, _), do: false

  def get(uuid, now) do
    with {:ok, value} <- Ecto.UUID.dump(uuid),
         [[id, settings]] <-
           Repo.query!(
             "SELECT user_id, sharing_settings FROM digests WHERE sharing_uuid=$1 LIMIT 1",
             [value],
             log: false
           ).rows,
         true <- public?(settings, now) do
      %{user: Accounts.get(id), digest: Digests.get_shared(uuid)}
    else
      _ -> nil
    end
  end

  defp unwrap({:ok, :not_found}), do: :not_found
  defp unwrap({:ok, result}), do: {:ok, result}
  defp unwrap({:error, error}), do: {:error, error}
end
