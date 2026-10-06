defmodule DawarichWeb.A12f3bReviewR1Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf
  setup do: seed()

  @tag a12f3b_review: "R1"
  test "R1 accepts per-form CSRF only for the submitted path and effective method", c do
    session = RailsUser.session(c.owner.id)

    for path <- ["/family", "/family.91001"], method <- ["PATCH", "PUT"] do
      token = RailsCsrf.masked_form_token(session, path, method)
      name = path <> method

      conn =
        request(
          c.owner,
          "POST",
          path,
          %{
            "_method" => String.downcase(method),
            "authenticity_token" => token,
            "family" => %{"name" => name}
          },
          [{"cookie", "_dawarich_session=" <> RailsUser.cookie(session)}]
        )

      assert conn.status == 302
      assert records("SELECT name FROM families WHERE id=91001") == [[name]]
    end

    for {path, method} <- [{"/other", "PATCH"}, {"/family", "POST"}, {"/family.91001", "PATCH"}] do
      conn =
        request(
          c.owner,
          "POST",
          "/family",
          %{
            "_method" => "patch",
            "authenticity_token" => RailsCsrf.masked_form_token(session, path, method),
            "family" => %{"name" => "Refused"}
          },
          [{"cookie", "_dawarich_session=" <> RailsUser.cookie(session)}]
        )

      assert conn.status == 422
      refute records("SELECT name FROM families WHERE id=91001") == [["Refused"]]
    end

    assert request(c.owner, "PATCH", "/family", %{"family" => %{"name" => "Global"}}).status ==
             302

    assert records("SELECT name FROM families WHERE id=91001") == [["Global"]]
  end
end
