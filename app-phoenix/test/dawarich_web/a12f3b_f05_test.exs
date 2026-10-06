defmodule DawarichWeb.A12f3bF05Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Families.Requests
  alias Dawarich.Jobs.Ownership

  setup do
    c = seed()
    Ownership.put!(Repo, "command:mail.family_location_request", :oban)
    c
  end

  @tag a12f3b_case: "F05a"
  test "location requests preserve target consent and expiry", c do
    Repo.query!("DELETE FROM family_location_requests")

    assert request(c.owner, "POST", "/family/location_requests", %{
             "target_user_id" => c.member.id
           }).status == 302

    assert [[id, expires]] = records("SELECT id,expires_at FROM family_location_requests")
    assert expires == ~N[2026-10-04 10:00:00.000000]

    assert request(c.owner, "PATCH", "/family/location_requests/#{id}/accept", %{
             "duration" => "1h"
           }).status == 302

    assert records("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[0]]

    assert request(c.member, "POST", "/family/location_requests/#{id}/accept", %{
             "_method" => "patch",
             "duration" => "1h"
           }).status == 302

    assert records("SELECT status,responded_at FROM family_location_requests WHERE id=$1", [id]) ==
             [[1, ~N[2026-10-03 10:00:00.000000]]]

    assert Accounts.settings(c.member.id)["family"]["location_sharing"]["duration"] == "1h"
    assert request(c.member, "PATCH", "/family/location_requests/#{id}/decline").status == 302
    assert records("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[1]]

    Repo.query!("UPDATE family_location_requests SET status=0,expires_at=$1 WHERE id=$2", [
      ~N[2026-10-03 10:00:00],
      id
    ])

    assert request(c.member, "PATCH", "/family/location_requests/#{id}/accept").status == 302
    assert records("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[0]]

    for target <- [c.owner.id, c.outsider.id] do
      assert request(c.owner, "POST", "/family/location_requests", %{"target_user_id" => target}).status ==
               302

      assert records("SELECT count(*) FROM family_location_requests") == [[1]]
    end
  end

  @tag a12f3b_case: "F05b"
  test "location request enqueue failure preserves the source committed request", c do
    Repo.query!("DELETE FROM family_location_requests")
    user = Map.put(c.owner, :timezone, "Europe/Berlin")

    assert {:ok, 500, _} =
             Requests.web_create(
               user,
               %{"target_user_id" => c.member.id},
               ~U[2026-10-03 10:00:00Z],
               enqueue: fn _, _ -> raise "synthetic outbox failure" end
             )

    assert records("SELECT requester_id,target_user_id,expires_at FROM family_location_requests") ==
             [[c.owner.id, c.member.id, ~N[2026-10-04 10:00:00.000000]]]

    assert records(
             "SELECT count(*) FROM job_outbox WHERE command_type='mail.family_location_request'"
           ) == [[0]]

    assert records("SELECT count(*) FROM notifications WHERE user_id=$1", [c.member.id]) == [[1]]

    assert request(c.owner, "POST", "/family/location_requests", %{
             "target_user_id" => c.member.id
           }).status == 302

    assert records("SELECT count(*) FROM family_location_requests") == [[1]]
  end
end
