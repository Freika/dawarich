defmodule DawarichWeb.PageRequest do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]

  @browser_like ~r/,\s*\*\/\*|\*\/\*\s*,/
  @page_types ~w(text/html */* application/xhtml+xml text/vnd.turbo-stream.html)

  def browser_like?(value), do: value =~ @browser_like

  def page_request?(conn),
    do: page_envelope?(DawarichWeb.AchievementPublicQuery.page_conn(conn))

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
