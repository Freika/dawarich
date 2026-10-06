defmodule DawarichWeb.A12f3bF03Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Families.WebDestroy
  setup do: seed()

  @tag a12f3b_case: "F03a"
  test "family removal preserves creator and actor boundaries", c do
    assert request(c.owner, "DELETE", "/family").status == 302
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[1]]
    assert request(c.owner, "DELETE", "/family/members/92001").status == 302
    assert records("SELECT count(*) FROM family_memberships WHERE id=92001") == [[1]]
    assert request(c.outsider, "DELETE", "/family/members/92002").status == 302
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[1]]

    Repo.query!(
      "INSERT INTO families(id,name,creator_id,created_at,updated_at) VALUES(91002,'Foreign',$1,now(),now())",
      [c.outsider.id]
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(91002,$1,0,now(),now())",
      [c.outsider.id]
    )

    assert request(c.outsider, "DELETE", "/family/members/92002").status == 404
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[1]]
    assert request(c.owner, "DELETE", "/family/members/92999").status == 404

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family}', $1) WHERE id=90102",
      [%{"location_sharing" => %{"enabled" => true, "duration" => "permanent"}}]
    )

    assert request(c.member, "DELETE", "/family/members/92002").status == 302
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
    assert Accounts.settings(c.member.id)["family"]["location_sharing"] == %{"enabled" => false}
    assert records("SELECT status FROM family_location_requests WHERE id=94001") == [[3]]
    assert request(c.owner, "DELETE", "/family").status == 302

    for table <- ~w(families family_memberships family_invitations family_location_requests) do
      predicate = if table == "families", do: "id", else: "family_id"
      assert records("SELECT count(*) FROM #{table} WHERE #{predicate}=91001") == [[0]]
    end
  end

  @tag a12f3b_case: "F03b"
  test "family delete failure does not replay committed removal", c do
    Repo.query!("DELETE FROM family_memberships WHERE id=92002")
    ctx = %{now: ~U[2026-10-03 10:00:00Z], self_hosted: true, locale: "en"}

    assert {:error, :publication_failed} =
             WebDestroy.run(Repo, c.owner, ctx,
               publish: fn _ -> raise "synthetic publication failure" end
             )

    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
    assert {:error, :not_in_family} = WebDestroy.run(Repo, c.owner, ctx)
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, nil)
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, previous) end)

    conn =
      DawarichWeb.FamilyActions.error(Plug.Test.conn("DELETE", "/family"), :publication_failed)

    assert conn.status == 500
    conn = request(c.owner, "DELETE", "/family")
    assert conn.status == 302
    refute Map.has_key?(conn.private, :dawarich_proxy)
  end
end
