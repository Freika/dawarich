Application.ensure_all_started(:crypto)
Application.put_env(:dawarich, :rails_secret, System.fetch_env!("RAILS_GUEST_TEST_SECRET"))

conn =
  Plug.Test.conn(:get, "http://127.0.0.1/stats?locale=en")
  |> Plug.Conn.fetch_query_params()
  |> DawarichWeb.RailsAuth.call([])
  |> DawarichWeb.Locale.call([])
  |> DawarichWeb.LayoutAssigns.call([])
  |> DawarichWeb.RequireUser.call([])

%{value: cookie} = Map.fetch!(conn.resp_cookies, "_dawarich_session")

IO.puts(
  Jason.encode!(%{
    status: conn.status,
    halted: conn.halted,
    location: List.first(Plug.Conn.get_resp_header(conn, "location")),
    cookie_count:
      Enum.count(Plug.Conn.get_resp_header(conn, "set-cookie"), fn line ->
        String.starts_with?(line, "_dawarich_session=")
      end),
    cookie: cookie
  })
)
