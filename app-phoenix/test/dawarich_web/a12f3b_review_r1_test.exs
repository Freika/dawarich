defmodule DawarichWeb.A12f3bReviewR1Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  setup do: seed()

  @tag a12f3b_review: "R1"
  test "native R1 retained acceptance binds per-form CSRF to its exact POST path", c do
    session = RailsUser.session(c.outsider.id)

    for path <- ["/family/memberships", "/family/memberships.html"] do
      token = RailsCsrf.masked_form_token(session, path, "POST")

      response =
        request(
          c.outsider,
          "POST",
          path,
          %{"token" => "a9fpl-pending", "authenticity_token" => token},
          [{"cookie", "_dawarich_session=" <> RailsUser.cookie(session)}]
        )

      assert response.status == 302
      assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[1]]
      Dawarich.Repo.query!("DELETE FROM family_memberships WHERE user_id=90103")
      Dawarich.Repo.query!("UPDATE family_invitations SET status=0 WHERE token='a9fpl-pending'")
    end

    for {path, method} <- [
          {"/other", "POST"},
          {"/family/memberships", "PATCH"},
          {"/family/memberships", "PUT"},
          {"/family/memberships.html", "POST"}
        ] do
      response =
        request(
          c.outsider,
          "POST",
          "/family/memberships",
          %{
            "token" => "a9fpl-pending",
            "authenticity_token" => RailsCsrf.masked_form_token(session, path, method)
          },
          [{"cookie", "_dawarich_session=" <> RailsUser.cookie(session)}]
        )

      assert response.status == 422
      assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[0]]
    end

    assert request(c.outsider, "POST", "/family/memberships", %{"token" => "a9fpl-pending"}).status ==
             302

    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[1]]
  end
end
