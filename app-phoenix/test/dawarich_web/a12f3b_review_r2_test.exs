defmodule DawarichWeb.A12f3bReviewR2Test do
  use Dawarich.IngestCase, async: true
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  import Phoenix.ConnTest
  import Plug.Conn
  @endpoint DawarichWeb.Endpoint

  @tag a12f3b_review: "R2"
  test "native R2 retired family suffix and method-override envelopes cannot mutate state" do
    user = RailsUser.insert!(%{id: 90301, email: "suffix@example.invalid"})
    session = RailsUser.session(user.id)

    for path <-
          ~w(/family.91001 /family/invitations.91001 /family/members/92002.html /family/location_sharing.json /family/location_requests/94001/accept.html /family/location_requests/94001/decline.html) do
      before = Repo.query!("SELECT count(*) FROM families").rows
      body = "_method=delete&family%5Bname%5D=forged"

      response =
        build_conn()
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(path, body)

      assert response.status == 404
      assert Repo.query!("SELECT count(*) FROM families").rows == before
    end
  end
end
