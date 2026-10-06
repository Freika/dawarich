defmodule DawarichWeb.A12f3bF04Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Families.WebInvitations

  setup do
    c = seed()
    Ownership.put!(Repo, "command:mail.family_invitation", :oban)
    c
  end

  @tag a12f3b_case: "F04a"
  test "family invitations create cancel and distinguish new from token", c do
    conn =
      request(c.owner, "POST", "/family/invitations", %{
        "family_invitation" => %{"email" => " NEW@EXAMPLE.TEST "}
      })

    assert conn.status == 302

    assert [[id, token, expires]] =
             records(
               "SELECT id,token,expires_at FROM family_invitations WHERE email='new@example.test'"
             )

    assert expires == ~N[2026-10-10 10:00:00.000000]

    assert [[%{"invitation_id" => ^id, "locale" => "en"}]] =
             records("SELECT payload FROM job_outbox WHERE command_type='mail.family_invitation'")

    assert request(c.owner, "POST", "/family/invitations", %{
             "family_invitation" => %{"email" => "new@example.test"}
           }).status == 302

    assert records("SELECT count(*) FROM family_invitations WHERE email='new@example.test'") == [
             [1]
           ]

    assert request(c.owner, "POST", "/family/invitations", %{
             "family_invitation" => %{"email" => "bad"}
           }).status == 302

    assert request(c.member, "DELETE", "/family/invitations/#{token}").status == 303
    assert request(c.outsider, "DELETE", "/family/invitations/#{token}").status == 302
    assert records("SELECT status FROM family_invitations WHERE id=$1", [id]) == [[0]]

    Repo.query!(
      "INSERT INTO families(id,name,creator_id,created_at,updated_at) VALUES(91002,'Foreign',$1,now(),now())",
      [c.outsider.id]
    )

    Repo.query!(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES(91002,$1,0,now(),now())",
      [c.outsider.id]
    )

    assert request(c.outsider, "DELETE", "/family/invitations/#{token}").status == 404
    assert records("SELECT status FROM family_invitations WHERE id=$1", [id]) == [[0]]
    assert request(c.owner, "DELETE", "/family/invitations/#{token}").status == 302
    assert records("SELECT status FROM family_invitations WHERE id=$1", [id]) == [[3]]
    Repo.query!("UPDATE family_invitations SET token='new' WHERE id=93001")
    assert request(c.owner, "GET", "/family/invitations/new").status == 404

    assert request(c.owner, "POST", "/family/invitations", %{
             "family_invitation" => %{"email" => "local@localhost"}
           }).status == 302

    assert records("SELECT count(*) FROM family_invitations WHERE email='local@localhost'") == [
             [1]
           ]
  end

  @tag a12f3b_case: "F04b"
  test "invitation acceptance persists membership once without retired mail", c do
    assert request(nil, "POST", "/family/memberships", %{"token" => "a9fpl-pending"}).status ==
             302

    assert request(c.owner, "POST", "/family/memberships", %{"token" => "a9fpl-pending"}).status ==
             302

    ctx = %{now: ~U[2026-10-03 10:00:00Z], locale: "en", self_hosted: true}

    assert {:error, _} =
             WebInvitations.accept(Repo, c.outsider, "a9fpl-pending", ctx,
               settled: fn -> raise "synthetic transaction abort" end
             )

    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[0]]

    Repo.query!("UPDATE family_invitations SET expires_at=$1 WHERE token='a9fpl-pending'", [
      DateTime.to_naive(ctx.now)
    ])

    assert request(c.outsider, "POST", "/family/memberships", %{"token" => "a9fpl-pending"}).status ==
             302

    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[1]]
    assert records("SELECT status FROM family_invitations WHERE token='a9fpl-pending'") == [[1]]
    assert records("SELECT count(*) FROM notifications WHERE user_id IN (90101,90103)") == [[2]]
    assert records("SELECT count(*) FROM job_outbox WHERE command_type LIKE 'mail.%'") == [[0]]

    again =
      request(Accounts.get(c.outsider.id), "POST", "/family/memberships", %{
        "token" => "a9fpl-pending"
      })

    assert Plug.Conn.get_resp_header(again, "location") == ["http://www.example.com/"]

    assert get_in(again.private, [:dawarich_rails_session_changes, "flash", "flashes", "alert"]) ==
             DawarichWeb.Translate.t(
               "en",
               "controllers.family.memberships.invitation_processed",
               %{}
             )

    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[1]]
    assert records("SELECT count(*) FROM notifications WHERE user_id IN (90101,90103)") == [[2]]
    System.put_env("SELF_HOSTED", "false")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [c.outsider.id])

    Repo.query!(
      "UPDATE family_invitations SET status=0,expires_at=$1 WHERE token='a9fpl-pending'",
      [~N[2026-10-04 10:00:00]]
    )

    Repo.query!("UPDATE users SET plan=1,active_until=$1 WHERE id=$2", [
      ~N[2026-10-03 09:59:59],
      c.owner.id
    ])

    Repo.query!("UPDATE families SET access_until=$1 WHERE id=91001", [~N[2026-11-03 10:00:00]])

    refused =
      request(Accounts.get(c.outsider.id), "POST", "/family/memberships", %{
        "token" => "a9fpl-pending"
      })

    assert Plug.Conn.get_resp_header(refused, "location") == ["http://www.example.com/"]

    assert records("SELECT access_until FROM families WHERE id=91001") == [
             [~N[2026-10-03 09:59:59.000000]]
           ]

    assert records("SELECT count(*) FROM family_memberships WHERE user_id=90103") == [[0]]
    assert records("SELECT status FROM family_invitations WHERE token='a9fpl-pending'") == [[0]]
  end
end
