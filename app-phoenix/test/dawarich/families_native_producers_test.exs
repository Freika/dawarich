defmodule Dawarich.FamiliesNativeProducersTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.{Accounts, Families, Repo}
  alias Dawarich.Test.FrameSeeds
  @now ~U[2026-10-03 10:00:00Z]
  setup do
    Code.ensure_loaded!(Dawarich.Accounts.User)
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, member: Accounts.get(90102) |> Map.put(:timezone, "UTC")}
  end

  defp jobs do
    Repo.query!(
      "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Families.EventsWorker'",
      [], log: false).rows
    |> List.flatten()
  end

  test "independent API consent persists ID-only invalidation and rollback publishes no intent",
       c do
    assert {:ok, 200, _} =
             Dawarich.Families.SharingUpdate.call(
               c.member,
               %{"enabled" => true, "duration" => "1h"},
               @now
             )

    assert Enum.sort(Enum.map(jobs(), & &1["user_id"])) == [90101, 90101, 90102, 90102]
    assert Enum.all?(jobs(), &(Enum.sort(Map.keys(&1)) == ~w(event_id kind user_id)))
    before = jobs()

    Repo.transaction(fn ->
      Dawarich.Families.SharingUpdate.call(c.member, %{"enabled" => false}, @now)
      Repo.rollback(:probe)
    end)

    assert jobs() == before
  end

  test "request and invitation housekeeping retain durable recipients after expiry", _c do
    Families.expire_invitations(Repo, ~N[2026-10-10 10:00:00])
    Families.expire_location_requests(Repo, ~N[2026-10-10 10:00:00])
    assert Enum.any?(jobs(), &(&1["kind"] == "invitation" and &1["user_id"] == 90101))
    assert Enum.any?(jobs(), &(&1["kind"] == "request" and &1["user_id"] == 90102))
    assert Enum.all?(jobs(), &(Enum.sort(Map.keys(&1)) == ~w(event_id kind user_id)))
  end

  test "independent API requests schedule expiry and accepted consent invalidation", c do
    member = c.member

    Repo.query!("UPDATE users SET settings=settings-'family' WHERE id=$1", [member.id],
      log: false
    )

    Dawarich.Jobs.Ownership.put!(Repo, "command:mail.family_location_request", :oban)
    owner = c.owner |> Map.put(:timezone, "UTC")

    {:ok, 201, {:object, fields}} =
      Dawarich.Families.Requests.create(
        owner,
        %{"target_user_id" => member.id},
        DateTime.add(@now, 86400)
      )

    {:object, request} = List.keyfind(fields, "request", 0) |> elem(1)
    id = List.keyfind(request, "id", 0) |> elem(1)
    assert Enum.count(jobs(), &(&1["kind"] == "request")) == 4

    {:ok, 200, _} =
      Dawarich.Families.Requests.respond(
        member,
        :accept,
        %{"id" => to_string(id), "duration" => "1h"},
        DateTime.add(@now, 86401)
      )

    assert Enum.any?(jobs(), &(&1["kind"] == "consent"))
  end

  test "independent invitation membership and Cloud access sync persist current recipients", _c do
    outsider = Accounts.get(90103)
    ctx = %{now: @now, self_hosted: true, locale: "en"}

    assert {:ok, 91001} =
             Dawarich.Families.WebInvitations.accept(Repo, outsider, "a9fpl-pending", ctx)

    assert Enum.sort(Enum.map(jobs(), & &1["user_id"])) == [90101, 90102, 90103]
    old = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
    end)

    Repo.query!(
      "UPDATE users SET plan=2,active_until=$1 WHERE id=90101",
      [DateTime.add(@now, 3600)], log: false)

    assert Dawarich.Families.MemberSync.run(Repo, 91001, now: @now)

    assert Enum.sort(for j <- jobs(), j["kind"] == "lapse", do: j["user_id"]) == [
             90101,
             90101,
             90102,
             90102,
             90103,
             90103
           ]
  end
end
