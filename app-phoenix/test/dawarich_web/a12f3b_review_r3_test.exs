defmodule DawarichWeb.A12f3bReviewR3Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.{Accounts, Repo}

  setup do: seed()

  @tag a12f3b_review: "R3"
  test "R3 departure rescues malformed settings after revocation and retains pending requests",
       c do
    System.put_env("SELF_HOSTED", "false")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family}', '[]'),plan=2,status=1,subscription_source=0 WHERE id=90102"
    )

    for actor <- [c.member, c.owner] do
      assert request(actor, "DELETE", "/family/members/92002").status == 302
      assert records("SELECT count(*) FROM family_memberships WHERE id=92002") == [[0]]
      assert records("SELECT plan,status,active_until FROM users WHERE id=90102") == [[0, 0, nil]]
      assert Accounts.settings(c.member.id)["family"] == []
      assert records("SELECT status FROM family_location_requests WHERE id=94001") == [[0]]
      assert records("SELECT count(*) FROM notifications WHERE user_id=90102") |> hd() |> hd() > 0

      if actor.id == c.member.id do
        Repo.query!(
          "INSERT INTO family_memberships(id,family_id,user_id,role,created_at,updated_at) VALUES(92002,91001,90102,1,now(),now())"
        )
      end
    end

    Repo.query!("UPDATE users SET settings=jsonb_set(settings,'{family}', '[]') WHERE id=90101")
    assert request(c.owner, "DELETE", "/family").status == 302
    assert records("SELECT count(*) FROM families WHERE id=91001") == [[0]]
    assert records("SELECT count(*) FROM family_memberships WHERE id=92001") == [[0]]
  end
end
