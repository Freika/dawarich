defmodule Dawarich.Test.RetiredM4Requests do
  import ExUnit.Assertions

  def assert_retired(conn) do
    response = DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
    assert response.status == 404

    assert :error ==
             Phoenix.Router.route_info(DawarichWeb.Router, conn.method, conn.path_info, conn.host)

    response
  end
end
