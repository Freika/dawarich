defmodule DawarichWeb.NativeM6AuthTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  test "native document authentication refuses malformed persisted settings before loading a page" do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "native-auth-shape-#{id}@dawarich.test"})
    conn = RailsUser.signed_in(id)
    Repo.query!("UPDATE users SET settings='[]'::jsonb WHERE id=$1", [id], log: false)

    before =
      Repo.query!("SELECT md5(to_jsonb(u)::text) FROM users u WHERE id=$1", [id], log: false).rows

    for path <- ~w(/map/v2 /trips/42 /family /s/missing) do
      response = get(conn, path)
      assert response.status == 422
      assert response.resp_body == ""
      assert Plug.Conn.get_resp_header(response, "location") == []
      assert Plug.Conn.get_resp_header(response, "cache-control") == ["private, no-store"]
    end

    assert Repo.query!("SELECT md5(to_jsonb(u)::text) FROM users u WHERE id=$1", [id], log: false).rows ==
             before

    assert Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows == [[0]]

    assert Repo.query!("SELECT count(*) FROM phoenix.rails_commands", [], log: false).rows == [
             [0]
           ]
  end
end
