defmodule DawarichWeb.NativeDataRequest do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def prepare(conn) do
    conn = normalize(conn)
    if conn.halted, do: conn, else: DawarichWeb.PageEnvelope.prepare(conn)
  end

  defp normalize(%{method: method, path_info: path} = conn) when method in ~w(GET HEAD) do
    case Regex.run(~r/\A(.+)\.([^\.\/]+)\z/, List.last(path) || "") do
      [_, name, format] ->
        candidate = List.replace_at(path, -1, name)
        route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", candidate, conn.host)

        if is_map(route) and route[:native_page] do
          if format == "html" or
               (:native_public in route.pipe_through and format == "turbo_stream") do
            conn
            |> Map.put(:path_info, candidate)
            |> Map.put(:request_path, "/" <> Enum.join(candidate, "/"))
            |> put_private(:native_page_format, format)
          else
            conn |> send_resp(422, "") |> halt()
          end
        else
          conn
        end

      _ ->
        conn
    end
  end

  defp normalize(conn), do: conn

  def call(conn, _) do
    conn = conn |> fetch_query_params() |> DawarichWeb.NativeM6Auth.call([])
    conn = put_private(conn, :native_data_document, true)

    if conn.halted, do: conn, else: envelope(conn)
  end

  defp envelope(conn) do
    if conn.query_params["format"] not in [nil, "html"] do
      conn |> send_resp(422, "") |> halt()
    else
      conn
    end
  end
end
