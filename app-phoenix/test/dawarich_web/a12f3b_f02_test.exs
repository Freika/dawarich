defmodule DawarichWeb.A12f3bF02Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  setup do: seed()

  @tag a12f3b_case: "F02a"
  test "family create and update preserve validation and ownership", c do
    conn = request(c.outsider, "POST", "/family", %{"family" => %{"name" => "  Native family  "}})
    assert conn.status == 302
    assert Plug.Conn.get_resp_header(conn, "location") == ["http://www.example.com/family"]

    assert [[family, "Native family", 0]] =
             records(
               "SELECT f.id,f.name,m.role FROM families f JOIN family_memberships m ON m.family_id=f.id WHERE m.user_id=$1",
               [c.outsider.id]
             )

    for method <- ["PATCH", "PUT", "POST"] do
      params = %{"family" => %{"name" => method}, "_method" => "patch"}
      updated = request(c.outsider, method, "/family", params)
      assert updated.status == 302
      assert records("SELECT name FROM families WHERE id=$1", [family]) == [[method]]
    end

    assert request(c.outsider, "PATCH", "/family", %{
             "family" => %{"name" => "bad"},
             "authenticity_token" => "invalid"
           }).status == 422

    assert request(nil, "POST", "/family", %{"family" => %{"name" => "guest"}}).status == 302

    assert request(c.member, "PATCH", "/family", %{"family" => %{"name" => "foreign"}}).status ==
             303
  end

  @tag a12f3b_case: "F02b"
  test "invalid family update preserves original name and flash contract", c do
    for value <- ["", String.duplicate("x", 51)] do
      conn = request(c.owner, "PATCH", "/family", %{"family" => %{"name" => value}})
      assert conn.status == 422
      assert conn.resp_body =~ "family[name]"
      assert records("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]
      refute get_in(conn.private, [:dawarich_rails_session_changes, "flash"])
    end

    assert request(c.owner, "PATCH", "/family", %{"family" => %{"name" => %{"nested" => "bad"}}}).status ==
             302

    assert records("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]

    assert request(c.outsider, "PATCH", "/family", %{"family" => %{"name" => "foreign"}}).status ==
             302

    assert records("SELECT name FROM families WHERE id=91001") == [["Leipzig Fixture Family"]]
  end
end
