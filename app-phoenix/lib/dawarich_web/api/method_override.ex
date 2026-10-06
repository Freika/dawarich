defmodule DawarichWeb.Api.MethodOverride do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.Api.{SourceParams, Transport}

  @methods ~w(GET HEAD PUT POST DELETE OPTIONS PATCH LINK UNLINK)
  def init(opts), do: opts

  def call(%{path_info: ["api", "v1", "mcp"]} = conn, _opts), do: conn

  def call(%{method: "POST", path_info: ["api", "v1" | _]} = conn, _opts) do
    if native?(conn) do
      conn = Transport.parse(conn)

      if conn.halted do
        conn
      else
        method = form_method(conn) || List.first(get_req_header(conn, "x-http-method-override"))
        method = if is_binary(method), do: String.upcase(method)

        if method in @methods,
          do: conn |> put_private(:dawarich_original_method, "POST") |> Map.put(:method, method),
          else: conn
      end
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp native?(conn) do
    not DawarichWeb.Strangler.handed_back?(conn.path_info) and
      Enum.any?(@methods, fn method ->
        case Phoenix.Router.route_info(DawarichWeb.Router, method, conn.path_info, conn.host) do
          %{slice: slice} -> DawarichWeb.Slices.owned?(slice)
          _ -> false
        end
      end)
  end

  defp form_method(conn) do
    case Transport.media_type(conn) do
      "application/x-www-form-urlencoded" ->
        case SourceParams.decode(conn.private[:dawarich_raw_body] || "") do
          {:ok, params} -> params["_method"]
          _ -> nil
        end

      "multipart/form-data" ->
        conn.body_params["_method"]

      _ ->
        nil
    end
  end
end
