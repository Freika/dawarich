defmodule DawarichWeb.Strangler do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, halt: 1]

  require Logger

  @browser_like ~r/,\s*\*\/\*|\*\/\*\s*,/
  @page_types ~w(text/html */* application/xhtml+xml text/vnd.turbo-stream.html)
  @page_pipelines [
    :browser,
    :insights,
    :rails_frame,
    :sharing,
    :sharing_unlock,
    :achievement_public,
    :trial_resume,
    :admin_writes,
    :trial_welcome,
    :public_home
  ]
  @keys %{"s" => "sharing", "invitations" => "family"}

  @constraints %{
    "/api/v1/tiles/points/:z/:x/:y" => %{"y" => ~r/\A[^\/]+\.mvt\z/},
    "/api/v1/tiles/tracks/:z/:x/:y" => %{"y" => ~r/\A[^\/]+\.mvt\z/},
    "/family/location_requests/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/route_videos/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/visits/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/settings/users/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/settings/users/:id/edit" => %{"id" => ~r/\A\d{1,18}\z/},
    "/tracks/:track_id/segments" => %{"track_id" => ~r/\A\d{1,18}\z/},
    "/points/:id/address" => %{"id" => ~r/\A\d{1,18}\z/},
    "/map/timeline_feeds/:id/track_info" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id/edit" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id/recalculate" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id/export" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:trip_id/notes" => %{"trip_id" => ~r/\A\d{1,18}\z/},
    "/trips/:trip_id/notes/:id" => %{"trip_id" => ~r/\A\d{1,18}\z/, "id" => ~r/\A\d{1,18}\z/},
    "/places/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/tags/:id/edit" => %{"id" => ~r/\A\d{1,18}\z/},
    "/tags/:id" => %{"id" => ~r/\A[1-9]\d{0,17}\z/},
    "/tracks/:track_id/segments/:id" => %{
      "track_id" => ~r/\A[1-9]\d{0,17}\z/,
      "id" => ~r/\A[1-9]\d{0,17}\z/
    },
    "/stats/:year" => %{"year" => ~r/\A\d{4}\z/},
    "/stats/:year/:month" => %{"year" => ~r/\A\d{4}\z/, "month" => ~r/\A(0?[1-9]|1[0-2])\z/},
    "/digests/:year" => %{"year" => ~r/\A\d{4}\z/},
    "/api/v1/digests/:year" => %{"year" => ~r/\A\d{4}\z/}
  }

  @coexistence_constraints %{
    "/api/v1/visits/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/visits/:id/possible_places" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/visits/:id/select_place" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/notes/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/photos/:id/thumbnail" => %{"id" => ~r/\A[0-9A-Za-z_-]{1,128}\z/},
    "/api/v1/photos/:id/thumbnail.jpg" => %{"id" => ~r/\A[0-9A-Za-z_-]{1,128}\z/},
    "/api/v1/places/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/tracks/:id" => %{"id" => ~r/\A\d+\z/},
    "/api/v1/tracks/:track_id/points" => %{"track_id" => ~r/\A\d+\z/},
    "/api/v1/families/location_requests/:id/accept" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/families/location_requests/:id/decline" => %{"id" => ~r/\A\d{1,18}\z/}
  }

  def browser_like?(value), do: value =~ @browser_like

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = DawarichWeb.PageEnvelope.prepare(conn)

    cond do
      conn.halted ->
        conn

      conn.private[:dawarich_api_pre_effect_pin] ->
        hand_back(conn)

      owned?(conn) ->
        conn
        |> Plug.Conn.put_private(
          :dawarich_native_api,
          native_api?(conn)
        )
        |> Plug.Conn.put_private(:dawarich_method, conn.method)
        |> Plug.Head.call([])

      native_api_error?(conn) ->
        DawarichWeb.RailsErrors.respond(conn, 404)

      Dawarich.Standalone.enabled?() ->
        conn = DawarichWeb.StandaloneRoutes.dispatch(conn)

        if conn.halted do
          conn
        else
          {reason, status} = standalone_rejection(conn)
          DawarichWeb.StandaloneError.respond(conn, reason, status)
        end

      DawarichWeb.TurboVisit.live_view_visit?(conn) ->
        DawarichWeb.TurboVisit.reload(conn)

      true ->
        hand_back(conn)
    end
  end

  defp hand_back(conn),
    do:
      conn
      |> original_method()
      |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
      |> halt()

  defp native_api_error?(%{path_info: ["api", "v1" | _]} = conn) do
    method = if conn.method == "HEAD", do: "GET", else: conn.method
    route = Phoenix.Router.route_info(DawarichWeb.Router, method, conn.path_info, conn.host)

    Dawarich.Standalone.enabled?() and not handed_back?(conn.path_info) and
      not DawarichWeb.ApiClosureRoutes.deferred?(conn) and
      (route == :error or
         (not handed_back?(conn.path_info, route) and slice_owned?(route, conn) and
            not rails_constraints?(route)))
  end

  defp native_api_error?(_conn), do: false

  defp original_method(conn),
    do: %{conn | method: conn.private[:dawarich_original_method] || conn.method}

  defp standalone_rejection(conn) do
    method = if conn.method == "HEAD", do: "GET", else: conn.method

    case Phoenix.Router.route_info(DawarichWeb.Router, method, conn.path_info, conn.host) do
      :error ->
        {"missing_route", 404}

      route ->
        cond do
          not rails_constraints?(route) ->
            {"route_constraint", 404}

          handed_back?(conn.path_info, route) ->
            {"route_disabled", 404}

          not slice_owned?(route, conn) ->
            {"slice_disabled", 404}

          Enum.any?(route.pipe_through, &(&1 in @page_pipelines)) and not page_request?(conn) ->
            {"unsupported_envelope", 422}

          true ->
            {"native_gate", 500}
        end
    end
  end

  defp owned?(conn) do
    method = if conn.method == "HEAD", do: "GET", else: conn.method

    case Phoenix.Router.route_info(DawarichWeb.Router, method, conn.path_info, conn.host) do
      :error ->
        false

      %{pipe_through: pipelines} = route ->
        not handed_back?(conn.path_info, route) and slice_owned?(route, conn) and
          rails_constraints?(route) and
          (not Enum.any?(pipelines, &(&1 in @page_pipelines)) or page_request?(conn)) and
          gate_open?(route, conn)
    end
  end

  def native_api?(%{path_info: ["api", "v1" | _]} = conn) do
    method = if conn.method == "HEAD", do: "GET", else: conn.method

    Dawarich.Standalone.enabled?() or
      Enum.any?([conn.path_info, format_path(conn.path_info)], fn path ->
        case Phoenix.Router.route_info(DawarichWeb.Router, method, path, conn.host) do
          %{native_api: true} -> true
          %{rails_key: key} when key in ~w(health ready) -> true
          _ -> false
        end
      end)
  end

  def native_api?(_conn), do: false

  defp format_path(["api", "v1", "tiles" | _] = path), do: path

  defp format_path(path) do
    case Regex.run(~r/\A(.+)\.([^\.\/]+)\z/, List.last(path)) do
      [_, name, _] -> List.replace_at(path, -1, name)
      _ -> path
    end
  end

  defp slice_owned?(%{slice: :api_shared, plug_opts: action}, %{method: "HEAD"})
       when action in [:photos, :thumbnail],
       do: Dawarich.Standalone.enabled?() and DawarichWeb.Slices.owned?(:api_shared)

  defp slice_owned?(%{slice: slice}, conn),
    do:
      (conn.method != "HEAD" or
         ((DawarichWeb.Slices.head?(slice) and native_api?(conn)) or slice == :cable)) and
        DawarichWeb.Slices.owned?(slice, native_api?(conn))

  defp slice_owned?(_route, _conn), do: true

  def gate_open?(%{rails_gate: {module, function}, path_params: params} = route, conn) do
    DawarichWeb.PageEnvelope.authenticate_first?(conn, route) or
      DawarichWeb.AuthenticatedPageGate.admit?(route, conn) or
      apply(module, function, [conn, params])
  rescue
    error -> handed_to_rails(conn, inspect(error.__struct__))
  catch
    :exit, reason -> handed_to_rails(conn, inspect(reason))
  end

  def gate_open?(%{rails_gate: _}, _conn), do: false
  def gate_open?(_route, _conn), do: true

  defp handed_to_rails(conn, detail) do
    Logger.info("[strangler] #{conn.request_path} handed to Rails: #{detail}")
    false
  end

  def rails_constraints?(%{route: route, path_params: params}),
    do:
      Enum.all?(Map.get(constraints(), route, %{}), fn {name, pattern} ->
        Regex.match?(pattern, params[name])
      end)

  defp constraints,
    do:
      if(Dawarich.Standalone.enabled?(),
        do: @constraints,
        else: Map.merge(@constraints, @coexistence_constraints)
      )

  def handed_back?([segment | _]),
    do: Map.get(@keys, segment, segment) in Application.get_env(:dawarich, :rails_routes, [])

  def handed_back?([]), do: "home" in Application.get_env(:dawarich, :rails_routes, [])

  defp handed_back?(_path, %{retired: true}), do: false

  defp handed_back?(path, route) do
    segment = List.first(path) || "home"

    keys =
      [Map.get(@keys, segment, segment), Map.get(route, :rails_key)] |> Enum.reject(&is_nil/1)

    Enum.any?(keys, &(&1 in Application.get_env(:dawarich, :rails_routes, [])))
  end

  def page_request?(conn),
    do: page_envelope?(DawarichWeb.AchievementPublicQuery.page_conn(conn))

  defp page_envelope?(%{private: %{dawarich_page_envelope: true}} = conn),
    do: DawarichWeb.PageEnvelope.accepted?(conn)

  defp page_envelope?(conn) do
    not String.contains?(List.last(conn.path_info) || "", ".") and
      not String.match?(header(conn, "x-requested-with"), ~r/XMLHttpRequest/i) and
      not valueless_query?(conn.query_string) and
      not format_param?(conn.query_string) and
      page_accept?(header(conn, "accept"))
  end

  defp valueless_query?(query) do
    query
    |> String.split("&", trim: true)
    |> Enum.any?(&(not String.contains?(&1, "=")))
  end

  defp format_param?(query) do
    Map.has_key?(Plug.Conn.Query.decode(query), "format")
  rescue
    Plug.Conn.InvalidQueryError -> true
  end

  defp page_accept?(accept) do
    types =
      for entry <- String.split(accept, ","),
          do: entry |> String.split(";") |> hd() |> String.trim() |> String.downcase()

    String.trim(accept) == "" or browser_like?(accept) or
      (Enum.all?(types, &(&1 in @page_types)) and Enum.any?(types, &(&1 in ~w(text/html */*))))
  end

  defp header(conn, name), do: conn |> get_req_header(name) |> Enum.join(", ")
end
