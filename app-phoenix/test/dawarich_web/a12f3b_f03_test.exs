defmodule DawarichWeb.A12f3bF03Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus
  alias Dawarich.{Accounts, Families, Repo}
  alias Dawarich.Families.WebDestroy
  setup do: seed()

  @tag a12f3b_case: "F03a"
  test "native F03a family removal preserves creator actor and foreign boundaries", c do
    assert {:error, :members_present} = Families.delete(scope(c.owner), opts())
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[1]]
    assert {:error, _} = Families.remove_member(scope(c.owner), 92001, opts())
    assert records("SELECT count(*) FROM family_memberships WHERE id=92001") == [[1]]
    assert {:error, :unauthorized} = Families.remove_member(scope(c.outsider), 92002, opts())
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[1]]

    Repo.query!(
      "INSERT INTO families(id,name,creator_id,created_at,updated_at) VALUES(91002,'Foreign',$1,now(),now())",
      [c.outsider.id]
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(91002,$1,0,now(),now())",
      [c.outsider.id]
    )

    assert {:error, :not_found} = Families.remove_member(scope(c.outsider), 92002, opts())
    assert {:error, :not_found} = Families.remove_member(scope(c.owner), 92999, opts())

    Repo.query!("UPDATE users SET settings=jsonb_set(settings,'{family}', $1) WHERE id=90102", [
      %{"location_sharing" => %{"enabled" => true, "duration" => "permanent"}}
    ])

    assert {:ok, %{self?: true}} = Families.remove_member(scope(c.member), 92002, opts())
    assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
    assert Accounts.settings(c.member.id)["family"]["location_sharing"] == %{"enabled" => false}
    assert records("SELECT status FROM family_location_requests WHERE id=94001") == [[3]]
    assert {:ok, _} = Families.delete(scope(c.owner), opts())

    for table <- ~w(families family_memberships family_invitations family_location_requests) do
      predicate = if table == "families", do: "id", else: "family_id"
      assert records("SELECT count(*) FROM #{table} WHERE #{predicate}=91001") == [[0]]
    end
  end

  @tag a12f3b_case: "F03b"
  test "native F03b failed publication does not replay committed family removal", c do
    Repo.query!("DELETE FROM family_memberships WHERE id=92002")
    ctx = %{now: ~U[2026-10-03 10:00:00Z], self_hosted: true, locale: "en"}

    assert {:error, :publication_failed} =
             WebDestroy.run(Repo, c.owner, ctx,
               publish: fn _ -> raise "synthetic publication failure" end
             )

    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
    assert {:error, :not_in_family} = WebDestroy.run(Repo, c.owner, ctx)
    assert {:error, :unauthorized} = Families.delete(scope(c.owner), opts())
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
  end
end
