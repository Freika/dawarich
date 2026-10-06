defmodule DawarichWeb.A12f3bReviewR5Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms

  setup do: seed()

  @tag a12f3b_review: "R5"
  test "R5 existing owner and member blank creation is an authorization redirect", c do
    for actor <- [c.owner, c.member] do
      conn = request(actor, "POST", "/family", %{"family" => %{"name" => ""}})
      assert conn.status == 303
      assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com/"]
      assert get_in(conn.private, [:dawarich_rails_session_changes, "flash", "flashes", "alert"])
      assert records("SELECT count(*) FROM families") == [[1]]
      assert records("SELECT count(*) FROM family_memberships") == [[2]]
    end
  end
end
