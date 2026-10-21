defmodule DawarichWeb.TagPageWritesRemovedTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser

  setup do
    RailsUser.insert!(%{id: 9821, email: "tag-page-writes@example.test"})

    Repo.insert_all("tags", [
      %{
        id: 98_211,
        user_id: 9821,
        name: "Kept",
        created_at: ~N[2026-10-01 10:00:00],
        updated_at: ~N[2026-10-01 10:00:00]
      }
    ])

    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    session = RailsUser.session(9821)
    %{session: session, token: DawarichWeb.RailsCsrf.masked_token(session)}
  end

  defp request(c, method, path, body) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("x-csrf-token", c.token)
    |> dispatch(DawarichWeb.Endpoint, method, path, body)
  end

  defp tags, do: Repo.query!("SELECT id, name FROM tags ORDER BY id").rows

  test "standalone tag page writes answer like an unknown page route and change nothing", c do
    unknown = request(c, "POST", "/no-such-page", "x=1").status

    for {method, path, body} <- [
          {"POST", "/tags", "tag%5Bname%5D=Created"},
          {"PATCH", "/tags/98211", "tag%5Bname%5D=Renamed"},
          {"DELETE", "/tags/98211", ""}
        ] do
      assert Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com") ==
               :error

      assert request(c, method, path, body).status == unknown, "#{method} #{path}"
      assert tags() == [[98_211, "Kept"]]
    end
  end
end
