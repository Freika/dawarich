defmodule DawarichWeb.Strangler do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, halt: 1]

  @browser_like ~r/,\s*\*\/\*|\*\/\*\s*,/
  @page_types ~w(text/html */* application/xhtml+xml text/vnd.turbo-stream.html)

  def browser_like?(value), do: value =~ @browser_like

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if owned?(conn),
      do: Plug.Head.call(conn, []),
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
        not handed_back?(conn.path_info) and slice_owned?(route, conn) and
          (:browser not in pipelines or page_request?(conn))
    end
  end

  defp slice_owned?(%{slice: slice}, conn),
    do: conn.method != "HEAD" and DawarichWeb.Slices.owned?(slice)

  defp slice_owned?(_route, _conn), do: true

  defp handed_back?([segment | _]),
    do: segment in Application.get_env(:dawarich, :rails_routes, [])

  defp handed_back?([]), do: false

  defp page_request?(conn) do
    not String.contains?(List.last(conn.path_info) || "", ".") and
      not String.match?(header(conn, "x-requested-with"), ~r/XMLHttpRequest/i) and
      not format_param?(conn.query_string) and
      page_accept?(header(conn, "accept"))
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
