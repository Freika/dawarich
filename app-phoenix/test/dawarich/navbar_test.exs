defmodule Dawarich.NavbarTest do
  use Dawarich.JobsCase

  import Ecto.Query

  alias Dawarich.{Accounts, Navbar, Repo}

  @now ~U[2026-09-26 12:00:00Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Pacific/Kiritimati")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)
  end

  defp user(id, fields \\ %{}) do
    stamp = ~N[2026-09-01 00:00:00]

    base = %{
      id: id,
      email: "nav#{id}@dawarich.test",
      encrypted_password: "",
      theme: "dark",
      settings: %{},
      status: 1,
      plan: 1,
      active_until: ~N[3026-01-01 00:00:00],
      subscription_source: 0,
      created_at: stamp,
      updated_at: stamp
    }

    Repo.insert_all("users", [Map.merge(base, fields)])
    Accounts.get(id)
  end

  defp family(owner_id, member_ids, access_until \\ nil) do
    stamp = ~N[2026-09-01 00:00:00]

    {1, [%{id: family_id}]} =
      Repo.insert_all(
        "families",
        [
          %{
            name: "F",
            creator_id: owner_id,
            access_until: access_until,
            created_at: stamp,
            updated_at: stamp
          }
        ],
        returning: [:id]
      )

    Repo.insert_all(
      "family_memberships",
      for(
        {id, role} <- [{owner_id, 0} | Enum.map(member_ids, &{&1, 1})],
        do: %{
          family_id: family_id,
          user_id: id,
          role: role,
          created_at: stamp,
          updated_at: stamp
        }
      )
    )
  end

  test "unread counts every unread row but lists the newest ten" do
    user = user(4401)
    user(4402)

    Repo.insert_all(
      "notifications",
      for(
        n <- 1..12,
        do: %{
          user_id: 4401,
          title: "U#{n}",
          content: "c",
          kind: rem(n, 3),
          created_at: NaiveDateTime.add(~N[2026-09-26 11:00:00], -n * 60),
          updated_at: ~N[2026-09-26 11:00:00]
        }
      )
    )

    Repo.insert_all("notifications", [
      %{
        user_id: 4401,
        title: "Read",
        content: "c",
        kind: 2,
        read_at: ~N[2026-09-26 11:00:00],
        created_at: ~N[2026-09-26 11:01:00],
        updated_at: ~N[2026-09-26 11:01:00]
      },
      %{
        user_id: 4402,
        title: "Foreign",
        content: "c",
        kind: 2,
        created_at: ~N[2026-09-26 11:02:00],
        updated_at: ~N[2026-09-26 11:02:00]
      }
    ])

    assert %{count: 12, items: items} = Navbar.load(user, now: @now, self_hosted: true).unread
    assert Enum.map(items, & &1.title) == Enum.map(1..10, &"U#{&1}")
    assert hd(items).kind == "warning"
    assert %{count: 0, items: []} = Navbar.unread(4403)
  end

  test "family: everyone on self-hosted; plan holders and members of a live plan on Cloud" do
    assert %{member: false, available: true} =
             Navbar.load(user(4410), now: @now, self_hosted: true).family

    assert %{available: true} =
             Navbar.load(user(4411, %{plan: 2}), now: @now, self_hosted: false).family

    user(4412, %{plan: 2})
    member = user(4413)
    family(4412, [4413])

    assert %{member: true, available: true, sharing: false} =
             Navbar.load(member, now: @now, self_hosted: false).family

    user(4414, %{plan: 1})
    lapsed = user(4415)
    family(4414, [4415])

    assert %{member: true, available: false} =
             Navbar.load(lapsed, now: @now, self_hosted: false).family

    user(4416, %{plan: 1})
    limited = user(4417)
    family(4416, [4417], ~N[2026-09-27 12:00:00])

    assert %{member: true, available: true} =
             Navbar.load(limited, now: @now, self_hosted: false).family

    deleted_owner = user(4418, %{plan: 2})
    deleted_member = user(4419)
    family(4418, [4419])

    from(u in "users", where: u.id == ^deleted_owner.id)
    |> Repo.update_all(set: [deleted_at: ~N[2026-09-01 00:00:00]])

    assert %{member: true, available: false} =
             Navbar.load(deleted_member, now: @now, self_hosted: false).family
  end

  test "sharing needs an enabled, unexpired setting" do
    user(4420)

    sharing = %{
      "family" => %{
        "location_sharing" => %{"enabled" => true, "expires_at" => "2026-09-27T12:00:00+02:00"}
      }
    }

    member = user(4421, %{settings: sharing})
    family(4420, [4421])
    assert Navbar.load(member, now: @now, self_hosted: true).family.sharing
    refute Navbar.load(member, now: ~U[2026-09-28 00:00:00Z], self_hosted: true).family.sharing

    non_member = user(4422, %{settings: sharing})
    refute Navbar.load(non_member, now: @now, self_hosted: true).family.sharing
  end

  test "trial days are counted in the user's zone, and a name Postgres does not know falls back" do
    until = ~N[2026-09-27 05:00:00]
    utc = user(4430, %{status: 2, active_until: until})

    east =
      user(4431, %{
        status: 2,
        active_until: until,
        settings: %{"timezone" => "Pacific/Kiritimati"}
      })

    rails_name =
      user(4432, %{status: 2, active_until: until, settings: %{"timezone" => "Berlin"}})

    assert Navbar.load(utc, now: @now, self_hosted: false).subscription.days == 0
    assert Navbar.load(east, now: @now, self_hosted: false).subscription.days == 0
    assert Navbar.load(rails_name, now: @now, self_hosted: false).subscription.days == 0
    assert Navbar.load(utc, now: @now, self_hosted: true).subscription == nil

    assert Navbar.load(user(4433, %{status: 2, active_until: until, subscription_source: 1}),
             now: @now,
             self_hosted: false
           ).subscription == nil

    assert %{expired: true, days: false} =
             Navbar.load(user(4434, %{active_until: ~N[2026-09-20 00:00:00]}),
               now: @now,
               self_hosted: false
             ).subscription

    assert Navbar.load(user(4435, %{subscription_source: 1}), now: @now, self_hosted: false).subscription ==
             nil
  end

  test "the changelog state follows consent and hosting, and a choice is saved" do
    assert Navbar.load(nil, now: @now, self_hosted: true).version.state == :badge
    prompt = user(4440)
    assert Navbar.load(prompt, now: @now, self_hosted: true).version.state == :prompt
    assert Navbar.load(prompt, now: @now, self_hosted: false).version.state == :widget
    declined = Navbar.put_changelog_consent(prompt, "declined")
    assert declined.changelog_consent == 0
    assert Navbar.load(Accounts.get(4440), now: @now, self_hosted: false).version.state == :badge

    ScratchRepo.query!(
      "INSERT INTO phoenix.app_version (latest_version, checked_at) VALUES ('999.0.0', $1)",
      [DateTime.add(@now, -3600)]
    )

    assert %{slug: "dawarich", update: true} =
             Navbar.load(prompt, now: @now, self_hosted: true).version

    assert %{slug: "dawarich-cloud", state: :widget, update: false} =
             Navbar.load(prompt, now: @now, self_hosted: false).version
  end

  test "onboarding shows until the setting is truthy" do
    assert Navbar.load(user(4450), now: @now, self_hosted: true).onboarding

    refute Navbar.load(user(4451, %{settings: %{"onboarding_completed" => true}}),
             now: @now,
             self_hosted: true
           ).onboarding
  end
end
