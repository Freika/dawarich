defmodule DawarichWeb.IntegrationActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Entitlements, Repo, Settings.Integrations}
  alias DawarichWeb.{Locale, RailsSession, RequestURL, SettingsActions, Translate}

  def init(action), do: action
  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()

  def call(conn, :update) do
    case admit(conn, ~w(PATCH PUT), ~w(service)) do
      :ok -> update(conn)
      {:error, status} -> SettingsActions.reject(conn, status)
    end
  end

  def admit(conn, methods, query_keys) do
    query = conn.assigns.api_query

    if Enum.any?(query, fn {key, value} -> key not in query_keys or not is_binary(value) end),
      do: {:error, 422},
      else: SettingsActions.admit(assign(conn, :api_query, %{}), methods)
  end

  def hosted?(conn),
    do: Map.get_lazy(conn.assigns, :self_hosted, &Dawarich.ReleaseMigration.self_hosted?/0)

  def locale(conn), do: Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

  def redirect(conn, path, flashes, status \\ 302) do
    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => flashes}})
    |> put_resp_header("location", RequestURL.base(conn) <> path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(status, "")
    |> halt()
  end

  defp update(conn) do
    user = conn.assigns.current_user
    params = conn.assigns.api_params

    cond do
      not Entitlements.future?(user.active_until, DateTime.utc_now()) ->
        redirect(
          conn,
          "/",
          %{
            "notice" =>
              Translate.t(locale(conn), "controllers.application.your_account_is_not_active", %{})
          },
          303
        )

      not Entitlements.full_access?(user, hosted?(conn), DateTime.utc_now()) ->
        redirect(
          conn,
          "/",
          %{
            "alert" =>
              Translate.t(
                locale(conn),
                "controllers.application.this_feature_requires_a_pro_plan",
                %{}
              )
          },
          303
        )

      not is_map(params["settings"]) or params["settings"] == %{} ->
        SettingsActions.reject(conn, 400)

      true ->
        case Integrations.save(Repo, user.id, params["settings"],
               self_hosted: hosted?(conn),
               locale: locale(conn)
             ) do
          {:ok, result} ->
            notices =
              if result.success and params["refresh_photos_cache"] not in [nil, false, ""],
                do: refresh(user.id, result.notices, locale(conn)),
                else: result.notices

            flashes = %{} |> flash("notice", notices) |> flash("alert", result.alerts)
            service = params["service"]

            path =
              "/settings/integrations" <>
                if(is_binary(service) and service != "",
                  do: "?" <> URI.encode_query(%{service: service}),
                  else: ""
                )

            redirect(conn, path, flashes)

          {:error, :invalid_settings} ->
            SettingsActions.reject(conn, 422)

          {:error, _} ->
            SettingsActions.reject(conn, 500)
        end
    end
  end

  defp refresh(id, notices, locale) do
    for pattern <- ["photos_#{id}_*", "photos_search/#{id}/*", "photo_thumbnail_#{id}_*"],
        do: clear(pattern, "0")

    notices ++ [Translate.t(locale, "services.settings.update.photo_cache_refreshed", %{})]
  end

  defp clear(pattern, cursor) do
    case Dawarich.Redis.cache_command(["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]) do
      {:ok, [next, keys]} ->
        if keys != [], do: Dawarich.Redis.cache_command(["UNLINK" | keys])
        if next != "0", do: clear(pattern, next)

      _ ->
        :ok
    end
  end

  defp flash(flashes, _type, []), do: flashes

  defp flash(flashes, type, messages) do
    message = Enum.join(messages, ". ")
    message = if byte_size(message) > 512, do: truncate(message, 509) <> "...", else: message
    Map.put(flashes, type, message)
  end

  defp truncate(message, limit),
    do:
      message
      |> String.codepoints()
      |> Enum.reduce_while("", fn point, acc ->
        if byte_size(acc <> point) <= limit, do: {:cont, acc <> point}, else: {:halt, acc}
      end)
end
