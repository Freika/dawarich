defmodule DawarichWeb.UserDataGate do
  @moduledoc false
  def native?(conn, _) do
    conn.method in ["GET", "POST"] and DawarichWeb.Strangler.page_request?(conn) and
      (conn.method != "GET" or Plug.Conn.get_req_header(conn, "content-length") in [[], ["0"]])
  end
end
