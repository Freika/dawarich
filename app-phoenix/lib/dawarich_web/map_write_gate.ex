defmodule DawarichWeb.MapWriteGate do
  @moduledoc false

  import Plug.Conn, only: [get_req_header: 2]
  alias DawarichWeb.{RailsAuth, RailsProxy}
  alias DawarichWeb.Api.Body

  def owned?(conn, _params) do
    (conn.query_string == "" or conn.path_info == ["points", "bulk_destroy"]) and
      get_req_header(conn, "x-dawarich-client") == [] and
      get_req_header(conn, "x-http-method-override") == [] and
      get_req_header(conn, "x-requested-with") == [] and
      single_session?(conn) and content?(conn) and not is_nil(RailsAuth.session_user(conn))
  end

  defp single_session?(conn) do
    names =
      for cookie <- get_req_header(conn, "cookie"),
          part <- String.split(cookie, ";"),
          do: part |> String.trim() |> String.split("=", parts: 2) |> hd()

    length(get_req_header(conn, "cookie")) == 1 and
      Enum.count(names, &(&1 == "_dawarich_session")) == 1
  end

  defp content?(conn) do
    not RailsProxy.Headers.chunked?(conn) and
      (Body.kind(conn) in [:form, :none] or multipart?(conn))
  end

  defp multipart?(conn) do
    with [type] <- get_req_header(conn, "content-type"),
         {:ok, "multipart", "form-data", %{"boundary" => _}} <- Plug.Conn.Utils.media_type(type),
         [length] <- get_req_header(conn, "content-length"),
         {size, ""} <- Integer.parse(length),
         do: size in 0..2_097_152,
         else: (_ -> false)
  end
end
