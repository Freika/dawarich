defmodule Dawarich.Settings.Integrations.Connection do
  @moduledoc false
  alias DawarichWeb.Translate

  def test(provider, settings, locale) do
    cond do
      blank?(settings[provider <> "_url"]) ->
        {:error, t(provider, locale, "url_is_missing")}

      provider != "teslamate" and blank?(settings[provider <> "_api_key"]) ->
        {:error, t(provider, locale, "api_key_is_missing")}

      true ->
        check(provider, settings, locale)
    end
  rescue
    _ -> failure(provider, locale)
  end

  defp check("airtrail" = provider, settings, locale) do
    case Dawarich.AirTrail.Client.flights(%{
           url: settings["airtrail_url"],
           api_key: settings["airtrail_api_key"],
           skip_ssl_verification: settings["airtrail_skip_ssl_verification"] == true
         }) do
      {:ok, _} ->
        success(provider, locale)

      {:error, message} ->
        {:error, t(provider, locale, "connection_failed_message", %{message: message})}
    end
  end

  defp check("teslamate" = provider, settings, locale) do
    client =
      Dawarich.Imports.Teslamate.Client.new(settings["teslamate_url"],
        username: settings["teslamate_username"],
        password: settings["teslamate_password"],
        api_token: settings["teslamate_api_token"],
        skip_ssl_verification: settings["teslamate_skip_ssl_verification"] == true,
        timeout: 5_000,
        max_attempts: 1
      )

    case Dawarich.Imports.Teslamate.Client.cars(client) do
      {:ok, _} -> success(provider, locale)
      {:error, _} -> failure(provider, locale)
    end
  end

  defp check("photoprism" = provider, settings, locale) do
    result =
      request(
        :get,
        settings["photoprism_url"],
        "/api/v1/photos?count=1&public=true",
        [{"authorization", "Bearer " <> settings["photoprism_api_key"]}],
        nil,
        settings["photoprism_skip_ssl_verification"]
      )

    case result do
      {:ok, status, _} when status in 200..299 -> success(provider, locale)
      {:ok, status, _} -> {:error, t(provider, locale, "connection_failed_code", %{code: status})}
      _ -> failure(provider, locale)
    end
  end

  defp check("immich" = provider, settings, locale) do
    start = DateTime.utc_now() |> DateTime.to_date() |> Date.to_iso8601()

    body =
      Jason.encode!(%{
        takenAfter: start <> "T00:00:00Z",
        size: 1,
        page: 1,
        order: "asc",
        withExif: true
      })

    headers = [{"x-api-key", settings["immich_api_key"]}]

    case request(
           :post,
           settings["immich_url"],
           "/api/search/metadata",
           headers,
           body,
           settings["immich_skip_ssl_verification"]
         ) do
      {:ok, status, body} when status in 200..299 ->
        case asset(body) do
          nil -> success(provider, locale)
          id -> thumbnail(settings, headers, id, locale)
        end

      {:ok, status, _} ->
        {:error, t(provider, locale, "connection_failed_code", %{code: status})}

      _ ->
        failure(provider, locale)
    end
  end

  defp thumbnail(settings, headers, id, locale) do
    path =
      "/api/assets/" <> URI.encode(id, &URI.char_unreserved?/1) <> "/thumbnail?size=preview"

    case request(
           :get,
           settings["immich_url"],
           path,
           headers,
           nil,
           settings["immich_skip_ssl_verification"]
         ) do
      {:ok, status, _} when status in 200..299 ->
        success("immich", locale)

      {:ok, 403, body} ->
        case Jason.decode(body) do
          {:ok, %{"message" => message}} when is_binary(message) ->
            if String.contains?(message, "asset.view"),
              do: {:error, t("immich", locale, "api_key_missing_permission_asset_view")},
              else: {:error, t("immich", locale, "thumbnail_check_failed_code", %{code: 403})}

          _ ->
            {:error, t("immich", locale, "thumbnail_check_failed_code", %{code: 403})}
        end

      {:ok, status, _} ->
        {:error, t("immich", locale, "thumbnail_check_failed_code", %{code: status})}

      _ ->
        failure("immich", locale)
    end
  end

  defp asset(body) do
    case Jason.decode(body) do
      {:ok, %{"assets" => %{"items" => [%{"id" => id} | _]}}} when is_binary(id) and id != "" ->
        id

      _ ->
        nil
    end
  end

  defp request(method, base, path, headers, body, skip) do
    case Dawarich.Photos.ProviderHTTP.request(
           method,
           base,
           path,
           [{"accept", "application/json"} | headers],
           body,
           skip
         ) do
      {:ok, status, _, data} -> {:ok, status, data}
      {:error, _} -> :error
    end
  end

  defp success(provider, locale), do: {:ok, t(provider, locale, "connection_verified")}

  defp failure(provider, locale),
    do:
      {:error, t(provider, locale, "connection_failed_message", %{message: "Connection failed"})}

  defp blank?(value),
    do: value in [nil, false, ""] or (is_binary(value) and String.trim(value) == "")

  defp t(provider, locale, key, args \\ %{}) do
    namespace =
      case provider do
        "airtrail" -> "air_trail"
        "teslamate" -> "tesla_mate"
        other -> other
      end

    Translate.t(locale, "services.#{namespace}.connection_tester.#{provider}_#{key}", args)
  end
end
