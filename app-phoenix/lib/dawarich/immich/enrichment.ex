defmodule Dawarich.Immich.Enrichment do
  @moduledoc false
  alias Dawarich.{I18n, Notifications, UserSettings}
  alias Dawarich.Immich.VerifyWorker

  def enqueue(id, assets, url, at), do: enqueue(Dawarich.Repo, Oban, id, assets, url, at)

  def enqueue(repo, oban, id, assets, url, at) do
    publish(repo, oban, %{"notification_id" => id, "assets" => assets, "immich_url" => url}, at)
    :ok
  end

  def verify(repo, oban, args, opts \\ []) do
    case repo.query!(
           "SELECT n.user_id,u.settings FROM notifications n JOIN users u ON u.id=n.user_id WHERE n.id=$1 AND u.deleted_at IS NULL FOR UPDATE OF n",
           [args["notification_id"]],
           log: false
         ).rows do
      [[user, settings]] -> verify_user(repo, oban, user, UserSettings.safe(settings), args, opts)
      _ -> :ok
    end
  end

  defp verify_user(repo, oban, user, settings, args, opts) do
    if settings["immich_url"] != args["immich_url"] or
         Dawarich.Ingest.Ruby.blank?(settings["immich_api_key"]) do
      finish(
        repo,
        user,
        settings,
        args,
        args["confirmed"],
        length(args["assets"] ++ args["unconfirmed"])
      )
    else
      {batch, remaining} = Enum.split(args["assets"], 20)
      {saved, pending} = Enum.split_with(batch, &confirmed?(settings, &1, opts))
      confirmed = args["confirmed"] + length(saved)
      unconfirmed = args["unconfirmed"] ++ pending
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

      cond do
        remaining != [] ->
          publish(
            repo,
            oban,
            Map.merge(args, %{
              "assets" => remaining,
              "confirmed" => confirmed,
              "unconfirmed" => unconfirmed
            }),
            now
          )

        unconfirmed != [] and args["pass"] < 3 ->
          publish(
            repo,
            oban,
            Map.merge(args, %{
              "assets" => unconfirmed,
              "pass" => args["pass"] + 1,
              "confirmed" => confirmed,
              "unconfirmed" => []
            }),
            DateTime.add(now, 30)
          )

        true ->
          finish(repo, user, settings, args, confirmed, length(unconfirmed))
      end
    end

    :ok
  end

  defp publish(_repo, oban, args, at) do
    {:ok, args} = VerifyWorker.args_from_command(1, args)

    Oban.insert!(
      oban,
      VerifyWorker.new(Map.put(args, "event_id", Ecto.UUID.generate()), scheduled_at: at)
    )
  end

  defp confirmed?(settings, asset, opts) do
    id = URI.encode(to_string(asset["immich_asset_id"]), &URI.char_unreserved?/1)
    headers = [{"x-api-key", settings["immich_api_key"]}, {"accept", "application/json"}]
    http = Keyword.get(opts, :http, &request/5)

    with {:ok, status, _, body} <-
           http.(
             :get,
             settings["immich_url"] <> "/api/assets/" <> id,
             headers,
             nil,
             settings["immich_skip_ssl_verification"]
           ),
         true <- status in 200..299,
         {:ok, %{"exifInfo" => exif}} when is_map(exif) <- Jason.decode(body) do
      Enum.all?(~w(latitude longitude), fn key ->
        with {:ok, actual} <- number(exif[key]),
             {:ok, expected} <- number(asset[key]),
             do: abs(actual - expected) <= 0.00001,
             else: (_ -> false)
      end)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp number(value) when is_number(value), do: {:ok, value}

  defp number(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {value, ""} -> {:ok, value}
      _ -> :error
    end
  end

  defp number(_), do: :error

  defp request(:get, url, headers, nil, skip) do
    headers = Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    case :httpc.request(
           :get,
           {String.to_charlist(url), headers},
           [timeout: 5000, connect_timeout: 5000, ssl: Dawarich.Photos.Thumbnail.ssl(skip)],
           body_format: :binary
         ) do
      {:ok, {{_, status, _}, headers, body}} -> {:ok, status, headers, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp finish(repo, user, settings, args, confirmed, unconfirmed) do
    locale = Dawarich.Mail.ExploreFeatures.locale(settings, nil)
    scope = "services.immich.enrich_photos."
    {:ok, title} = I18n.t(locale, scope <> "result_title", %{})
    {:ok, content} = I18n.t(locale, scope <> "confirmed", %{"count" => confirmed})

    content =
      if unconfirmed > 0 do
        {:ok, pending} = I18n.t(locale, scope <> "unconfirmed", %{"count" => unconfirmed})
        content <> " " <> pending
      else
        content
      end

    Notifications.update_with_broadcast!(repo, user, args["notification_id"], %{
      "title" => title,
      "content" => content,
      "kind" => if(unconfirmed > 0, do: :warning, else: :info),
      "read_at" => nil
    })
  end
end
