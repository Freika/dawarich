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
    :trial_resume,
    :admin_writes,
    :trial_welcome,
    :public_home
  ]
  @keys %{"s" => "sharing", "invitations" => "family"}

  @constraints %{
    "/family/location_requests/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/visits/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/visits/:id/possible_places" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/visits/:id/select_place" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/notes/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/route_videos/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/visits/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/settings/users/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/settings/users/:id/edit" => %{"id" => ~r/\A\d{1,18}\z/},
    "/tracks/:track_id/segments" => %{"track_id" => ~r/\A\d{1,18}\z/},
    "/points/:id/address" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/photos/:id/thumbnail" => %{"id" => ~r/\A[0-9A-Za-z_-]{1,128}\z/},
    "/api/v1/photos/:id/thumbnail.jpg" => %{"id" => ~r/\A[0-9A-Za-z_-]{1,128}\z/},
    "/api/v1/places/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/tracks/:id" => %{"id" => ~r/\A\d+\z/},
    "/api/v1/tracks/:track_id/points" => %{"track_id" => ~r/\A\d+\z/},
    "/map/timeline_feeds/:id/track_info" => %{"id" => ~r/\A\d{1,18}\z/},
    "/trips/:id" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/families/location_requests/:id/accept" => %{"id" => ~r/\A\d{1,18}\z/},
    "/api/v1/families/location_requests/:id/decline" => %{"id" => ~r/\A\d{1,18}\z/},
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

  def browser_like?(value), do: value =~ @browser_like

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if owned?(conn),
      do: conn |> Plug.Conn.put_private(:dawarich_method, conn.method) |> Plug.Head.call([]),
      else:
        conn
        |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
        |> halt()
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

  defp slice_owned?(%{slice: slice}, conn),
    do: conn.method != "HEAD" and DawarichWeb.Slices.owned?(slice)

  defp slice_owned?(_route, _conn), do: true

  def gate_open?(%{rails_gate: {module, function}, path_params: params}, conn) do
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
      Enum.all?(Map.get(@constraints, route, %{}), fn {name, pattern} ->
        Regex.match?(pattern, params[name])
      end)

  def handed_back?([segment | _]),
    do: Map.get(@keys, segment, segment) in Application.get_env(:dawarich, :rails_routes, [])

  def handed_back?([]), do: "home" in Application.get_env(:dawarich, :rails_routes, [])

  defp handed_back?(path, route) do
    segment = List.first(path) || "home"

    keys =
      [Map.get(@keys, segment, segment), Map.get(route, :rails_key)] |> Enum.reject(&is_nil/1)

    Enum.any?(keys, &(&1 in Application.get_env(:dawarich, :rails_routes, [])))
  end

  def page_request?(conn) do
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
