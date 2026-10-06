defmodule DawarichWeb.Api.MethodOverride do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.Api.{SourceParams, Transport}

  @methods ~w(GET HEAD PUT POST DELETE OPTIONS PATCH LINK UNLINK)
  def init(opts), do: opts

  def call(%{path_info: ["api", "v1", "mcp"]} = conn, _opts), do: conn

  def call(%{method: "POST", path_info: ["api", "v1" | _]} = conn, _opts) do
    slices = candidate_slices(conn)

    cond do
      DawarichWeb.Strangler.handed_back?(conn.path_info) or
        DawarichWeb.ApiClosureRoutes.deferred?(conn) or not original_owned?(conn) ->
        conn

      override_possible?(conn) and Enum.any?(slices, &(not DawarichWeb.Slices.owned?(&1))) ->
        put_private(conn, :dawarich_api_pre_effect_pin, true)

      Enum.any?(slices, &DawarichWeb.Slices.owned?/1) ->
        override(conn)

      true ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp override(conn) do
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
  end

  defp candidate_slices(conn),
    do:
      for(
        method <- @methods,
        %{slice: slice} <- [
          Phoenix.Router.route_info(DawarichWeb.Router, method, conn.path_info, conn.host)
        ],
        do: slice
      )

  defp override_possible?(conn),
    do:
      get_req_header(conn, "x-http-method-override") != [] or
        Transport.media_type(conn) in ~w(application/x-www-form-urlencoded multipart/form-data)

  defp original_owned?(conn) do
    case Phoenix.Router.route_info(DawarichWeb.Router, conn.method, conn.path_info, conn.host) do
      %{slice: slice} -> DawarichWeb.Slices.owned?(slice)
      _ -> true
    end
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
