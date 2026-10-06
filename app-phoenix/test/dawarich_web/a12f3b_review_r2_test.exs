defmodule DawarichWeb.A12f3bReviewR2Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.Accounts
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  alias Dawarich.Test.FamilyForms.Router, as: FamilyReviewRouter
  setup do: seed()

  @tag a12f3b_review: "R2"
  test "R2 declared router dispatches formatted forms after POST overrides", c do
    for {verb, path} <- [
          {"PATCH", "/family.91001"},
          {"POST", "/family.91001"},
          {"POST", "/family/members/92002.html"},
          {"POST", "/family/location_sharing.json"},
          {"POST", "/family/location_requests/94001/accept.html"}
        ] do
      assert Phoenix.Router.route_info(FamilyReviewRouter, verb, path, "www.example.com") !=
               :error
    end

    for path <- ["/family", "/family.91001"], method <- ["patch", "put"] do
      name = path <> method

      conn =
        router_request(c.owner, "POST", path, %{
          "_method" => method,
          "family" => %{"name" => name}
        })

      assert conn.status == 302
      assert records("SELECT name FROM families WHERE id=91001") == [[name]]
    end

    sharing =
      router_request(c.member, "POST", "/family/location_sharing.json", %{
        "_method" => "patch",
        "enabled" => false
      })

    assert sharing.status == 200
    assert Accounts.settings(c.member.id)["family"]["location_sharing"] == %{"enabled" => false}

    assert router_request(c.member, "POST", "/family/location_requests/94001/decline.html", %{
             "_method" => "patch"
           }).status == 302

    assert records("SELECT status FROM family_location_requests WHERE id=94001") == [[2]]

    assert router_request(c.owner, "POST", "/family/members/92002.html", %{"_method" => "delete"}).status ==
             302

    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]

    assert router_request(c.owner, "POST", "/family.91001", %{"_method" => "delete"}).status ==
             302

    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
    assert router_request(c.owner, "GET", "/family/invitations/new.html").status == 404
  end

  defp router_request(user, method, path, params \\ %{}) do
    session = RailsUser.session(user.id)
    params = Map.put_new(params, "authenticity_token", RailsCsrf.masked_token(session))

    Plug.Test.conn(method, path, Plug.Conn.Query.encode(params))
    |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
    |> Plug.Conn.put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
    |> Plug.Conn.assign(:now, ~U[2026-10-03 10:00:00Z])
    |> FamilyReviewRouter.call(FamilyReviewRouter.init([]))
  end
end
