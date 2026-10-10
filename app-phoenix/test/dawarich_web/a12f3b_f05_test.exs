defmodule DawarichWeb.A12f3bF05Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus
  alias Dawarich.{Repo, Accounts, Families}
  alias Dawarich.Families.Requests
  alias Dawarich.Jobs.Ownership

  setup do
    c = seed()
    Ownership.put!(Repo, "command:mail.family_location_request", :oban)
    c
  end

  @tag a12f3b_case: "F05a"
  test "native F05a location requests preserve target consent and expiry", c do
    Repo.query!("DELETE FROM family_location_requests")

    assert {:ok, _} =
             Families.request_location(scope(c.owner), %{"target_user_id" => c.member.id}, opts())

    assert [[id, ~N[2026-10-04 10:00:00.000000]]] =
             records("SELECT id,expires_at FROM family_location_requests")

    assert {:error, :unauthorized} =
             Families.respond_location(scope(c.owner), id, :accept, %{"duration" => "1h"}, opts())

    assert records("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[0]]

    assert {:ok, _} =
             Families.respond_location(
               scope(c.member),
               id,
               :accept,
               %{"duration" => "1h"},
               opts()
             )

    assert [[1, responded]] =
             records("SELECT status,responded_at FROM family_location_requests WHERE id=$1", [id])

    assert NaiveDateTime.compare(responded, ~N[2026-10-03 10:00:00]) != :lt
    assert NaiveDateTime.diff(responded, ~N[2026-10-03 10:00:00]) < 60
    assert Accounts.settings(c.member.id)["family"]["location_sharing"]["duration"] == "1h"

    assert {:error, :expired} =
             Families.respond_location(scope(c.member), id, :decline, %{}, opts())

    assert records("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[1]]

    Repo.query!("UPDATE family_location_requests SET status=0,expires_at=$1 WHERE id=$2", [
      ~N[2026-10-03 10:00:00],
      id
    ])

    assert {:error, :expired} =
             Families.respond_location(
               scope(c.member),
               id,
               :accept,
               %{},
               Keyword.put(opts(), :clock, fn -> ~U[2026-10-03 10:00:00Z] end)
             )

    assert records("SELECT status FROM family_location_requests WHERE id=$1", [id]) == [[0]]

    for target <- [c.owner.id, c.outsider.id] do
      assert {:error, _} =
               Families.request_location(scope(c.owner), %{"target_user_id" => target}, opts())

      assert records("SELECT count(*) FROM family_location_requests") == [[1]]
    end
  end

  @tag a12f3b_case: "F05b"
  test "native F05b retry preserves the source committed request after enqueue failure", c do
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

    assert {:error, _} =
             Families.request_location(scope(c.owner), %{"target_user_id" => c.member.id}, opts())

    assert records("SELECT count(*) FROM family_location_requests") == [[1]]
  end
end
