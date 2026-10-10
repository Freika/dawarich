defmodule DawarichWeb.NativeM6Envelope do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def prepare(conn) do
    parts = String.split(List.last(conn.path_info) || "", ".")

    if length(parts) > 1 do
      format = List.last(parts)
      name = parts |> Enum.drop(-1) |> Enum.join(".")
      path = List.replace_at(conn.path_info, -1, name)
      method = if conn.method == "HEAD", do: "GET", else: conn.method

      case Phoenix.Router.route_info(DawarichWeb.Router, method, path, conn.host) do
        %{pipe_through: pipelines} when is_list(pipelines) ->
          if Enum.any?(pipelines, &(&1 in [:native_m6_browser, :native_map_retired])) do
            conn
            |> Map.put(:path_info, path)
            |> Map.put(:request_path, "/" <> Enum.join(path, "/"))
            |> put_private(:native_m6_format, format)
          else
            conn
          end

        _ ->
          conn
      end
    else
      conn
    end
  end

  def call(conn, _) do
    format = conn.private[:native_m6_format] || conn.query_params["format"]
    conn = if format == "html", do: put_req_header(conn, "accept", "text/html"), else: conn

    conn =
      register_before_send(conn, fn response ->
        response
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
      end)

    cond do
      conn.method not in ~w(GET HEAD) ->
        refuse(conn, 405)

      format not in [nil, "html"] ->
        refuse(conn, 422)

      Enum.any?(
        get_req_header(conn, "x-requested-with"),
        &(String.downcase(&1) == "xmlhttprequest")
      ) ->
        refuse(conn, 422)

      not html?(conn) ->
        refuse(conn, 422)

      true ->
        conn
    end
  end

  defp html?(conn) do
    values = get_req_header(conn, "accept")

    values == [] or
      Enum.any?(values, fn value ->
        Enum.any?(String.split(value, ","), fn item ->
          type = item |> String.split(";") |> hd() |> String.trim() |> String.downcase()
          type in ["", "text/html", "application/xhtml+xml", "*/*"]
        end)
      end)
  end

  defp refuse(conn, status),
    do: conn |> put_resp_header("cache-control", "no-store") |> send_resp(status, "") |> halt()
end
