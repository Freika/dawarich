defmodule DawarichWeb.TrekSourceActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Entitlements, Repo}
  alias Dawarich.Imports.Trek.{Sources, Client}

  alias DawarichWeb.{
    IntegrationActions,
    SettingsActions,
    WebFormParams,
    Translate,
    RailsSession,
    RequestURL
  }

  @integrations "/settings/integrations?service=trek"

  def init(action), do: action
  def enabled?(_conn, _params), do: Dawarich.Standalone.enabled?()

  def call(conn, action) do
    conn = fetch_query_params(conn)

    with true <- query?(conn.query_params),
         {:ok, conn, params} <- WebFormParams.params(conn, query: true, repeated: ["trip_ids[]"]),
         params = Map.merge(params, conn.query_params),
         conn = conn |> assign(:api_params, params) |> assign(:api_query, %{}),
         :ok <- SettingsActions.admit(conn, methods(action), locale: true) do
      conn |> DawarichWeb.Locale.call([]) |> authorize(action)
    else
      false -> SettingsActions.reject(conn, 422)
      {:error, 302} -> unauthenticated(conn)
      {:error, status} when is_integer(status) -> SettingsActions.reject(conn, status)
      {_, conn} -> SettingsActions.reject(conn, 422)
    end
  rescue
    _ -> SettingsActions.reject(conn, 500)
  end

  defp query?(query) do
    Enum.all?(query, fn
      {"locale", locale} -> locale in DawarichWeb.Locale.locales()
      {"format", "html"} -> true
      _ -> false
    end)
  end

  defp unauthenticated(conn) do
    locale = IntegrationActions.locale(conn)
    conn = assign(conn, :locale, locale)

    if conn.method == "GET" do
      DawarichWeb.RequireUser.call(conn, [])
    else
      IntegrationActions.redirect(conn, "/users/sign_in", %{
        "alert" => Translate.t(locale, "devise.failure.unauthenticated", %{})
      })
    end
  end

  defp methods(:select_trips), do: ["GET"]
  defp methods(:destroy), do: ["DELETE"]
  defp methods(_), do: ["POST"]

  defp authorize(conn, action) do
    user = conn.assigns.current_user
    now = DateTime.utc_now()

    cond do
      not Entitlements.future?(user.active_until, now) ->
        application_redirect(conn, "/", "notice", "your_account_is_not_active")

      not Entitlements.full_access?(user, IntegrationActions.hosted?(conn), now) ->
        target =
          case get_req_header(conn, "referer") do
            [url] -> url
            _ -> "/"
          end

        application_redirect(conn, target, "alert", "this_feature_requires_a_pro_plan")

      action == :create ->
        create(conn)

      true ->
        case Sources.get(
               Repo,
               user.id,
               String.replace_suffix(conn.path_params["id"], ".html", "")
             ) do
          nil -> SettingsActions.reject(conn, 404)
          source -> perform(conn, action, source)
        end
    end
  end

  defp create(conn) do
    attrs = conn.assigns.api_params["trip_source"]

    if is_map(attrs) and attrs != %{} do
      case Sources.connect(Repo, conn.assigns.current_user.id, attrs, options(conn)) do
        {:ok, id} -> done(conn, select_path(id), "create.connected_choose_trips")
        error -> failure(conn, error)
      end
    else
      SettingsActions.reject(conn, 400)
    end
  end

  defp perform(conn, :destroy, source) do
    case Sources.disconnect(source) do
      {:ok, _} -> done(conn, @integrations, "destroy.source_removed_trips_kept")
      error -> failure(conn, error)
    end
  end

  defp perform(conn, action, source) do
    cond do
      source.status != 0 ->
        failure(conn, {:error, :disabled})

      source.importing ->
        failure(conn, {:error, :importing})

      action == :select_trips ->
        selection(conn, source)

      action == :import_trips ->
        import_trips(conn, source)

      action == :sync ->
        case Sources.sync(source) do
          {:ok, _} -> done(conn, @integrations, "sync.sync_queued")
          error -> failure(conn, error)
        end
    end
  end

  defp selection(conn, source) do
    case Sources.remote(source, options(conn)) do
      {:ok, trips} ->
        DawarichWeb.TrekSelection.render(conn, source, trips, Sources.selected(source))

      error ->
        failure(conn, error)
    end
  end

  defp import_trips(conn, source) do
    ids =
      conn.assigns.api_params["trip_ids"]
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.uniq()

    if ids == [] do
      case Sources.clear(source) do
        {:ok, _} -> done(conn, @integrations, "import_trips.no_trips_selected")
        error -> failure(conn, error)
      end
    else
      with {:ok, trips} <- Sources.remote(source, options(conn)) do
        available = trips |> Enum.filter(&Sources.selectable?/1) |> Enum.map(&to_string(&1["id"]))
        ids = Enum.filter(ids, &(&1 in available))

        if ids == [] do
          done(
            conn,
            select_path(source.id),
            "import_trips.select_at_least_one_dated_trip",
            "alert"
          )
        else
          case Sources.select(source, ids) do
            {:ok, _} -> done(conn, @integrations, "import_trips.trips_are_now_syncing")
            error -> failure(conn, error)
          end
        end
      else
        error -> failure(conn, error)
      end
    end
  end

  defp failure(conn, {:error, :importing}),
    do: done(conn, @integrations, "sync.source_importing", "alert")

  defp failure(conn, {:error, :disabled}),
    do: done(conn, @integrations, "sync.source_disabled", "alert")

  defp failure(conn, {:error, :not_found}), do: SettingsActions.reject(conn, 404)
  defp failure(conn, {:error, %Client.Error{message: message}}), do: alert(conn, message)
  defp failure(conn, {:error, message}) when is_binary(message), do: alert(conn, message)
  defp failure(conn, _), do: SettingsActions.reject(conn, 500)

  defp alert(conn, message),
    do: IntegrationActions.redirect(conn, @integrations, %{"alert" => message})

  defp select_path(id), do: "/settings/trek_sources/#{id}/select_trips"

  defp options(conn),
    do: [self_hosted?: IntegrationActions.hosted?(conn), locale: IntegrationActions.locale(conn)]

  defp done(conn, path, key, type \\ "notice") do
    IntegrationActions.redirect(conn, path, %{
      type => Translate.t(IntegrationActions.locale(conn), "settings.trek_sources." <> key, %{})
    })
  end

  defp application_redirect(conn, path, type, key) do
    message = Translate.t(IntegrationActions.locale(conn), "controllers.application." <> key, %{})

    target =
      if String.starts_with?(path, ["http://", "https://"]),
        do: path,
        else: RequestURL.base(conn) <> path

    conn
    |> RailsSession.stage(%{"flash" => %{"discard" => [], "flashes" => %{type => message}}})
    |> put_resp_header("location", target)
    |> put_resp_content_type("text/html")
    |> send_resp(303, "")
    |> halt()
  end
end
