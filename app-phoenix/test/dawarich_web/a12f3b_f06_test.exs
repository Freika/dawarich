defmodule DawarichWeb.A12f3bF06Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus
  alias Dawarich.{Accounts, Repo, Families}
  alias DawarichWeb.FamilyLocations
  setup do: seed()
  @now ~U[2026-10-03 10:00:00Z]

  @tag a12f3b_case: "F06a"
  test "native F06a duration and audience persist while independent JSON values survive", c do
    assert {:ok, config} =
             Families.set_sharing(
               scope(c.member),
               %{"enabled" => "on", "duration" => "2"},
               opts()
             )

    assert config["enabled"]
    assert config["duration"] == "2"
    assert DateTime.from_iso8601(config["expires_at"]) |> elem(1) == ~U[2026-10-03 12:00:00Z]

    assert {:error, :invalid_input} =
             Families.set_sharing(
               scope(c.member),
               %{
                 "enabled" => %{"nested" => false},
                 "duration" => "1h",
                 "share_history" => "true"
               },
               opts()
             )

    assert {:ok, 200, _} =
             legacy_sharing(c.member, %{
               "enabled" => %{"nested" => false},
               "duration" => "1h",
               "share_history" => "true"
             })

    assert Accounts.settings(c.member.id)["family"]["location_sharing"]["share_history"]

    assert {:ok, 200, {:object, pairs}} =
             legacy_sharing(c.member, %{"enabled" => true, "duration" => "1h", "locale" => "de"})

    fields = Map.new(pairs)

    assert fields["message"] ==
             DawarichWeb.Translate.t(
               "de",
               "services.families.update_location_sharing.enabled_for_hours",
               %{"count" => 1}
             )

    assert fields["expires_at_formatted"] ==
             DawarichWeb.LocalizedDate.time("de", ~N[2026-10-03 13:00:00], "short_with_time")

    Repo.query!(
      "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,1791021600,ST_SetSRID(ST_MakePoint(12.37,51.34),4326),now(),now())",
      [c.member.id]
    )

    response = locations(c.owner)
    assert response.status == 200
    assert [%{"user_id" => 90102}] = Jason.decode!(response.resp_body)

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,expires_at}',to_jsonb($1::text)) WHERE id=90102",
      ["2026-10-03T10:00:00Z"]
    )

    assert Jason.decode!(locations(c.owner).resp_body) == []

    assert {:error, :unauthorized} =
             Families.set_sharing(scope(c.outsider), %{"enabled" => true}, opts())

    assert {:ok, 404, {:object, refusal}} = legacy_sharing(c.outsider, %{"enabled" => true})

    assert Map.new(refusal)["error"] ==
             DawarichWeb.Translate.t(
               "en",
               "controllers.family.location_sharing.user_is_not_part_of_a_family",
               %{}
             )

    System.put_env("SELF_HOSTED", "false")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    Repo.query!("UPDATE families SET access_until=$1 WHERE id=91001", [DateTime.to_naive(@now)])
    Repo.query!("UPDATE users SET plan=1 WHERE id=90101")

    assert {:error, :expired} =
             Families.set_sharing(scope(c.member), %{"enabled" => false}, opts())

    assert {:ok, 200, _} = legacy_sharing(c.member, %{"enabled" => false})
    assert Accounts.settings(c.member.id)["family"]["location_sharing"] == %{"enabled" => false}
  end

  @tag a12f3b_case: "F06b"
  test "native F06b malformed consent refuses before effects and independent JSON remains terminal",
       c do
    Repo.query!("UPDATE users SET settings=jsonb_set(settings,'{family}', '[]') WHERE id=90102")

    assert {:error, :unavailable} =
             Families.set_sharing(
               scope(c.member),
               %{"enabled" => true, "duration" => "1h"},
               opts()
             )

    assert Accounts.settings(c.member.id)["family"] == []
    Repo.query!("UPDATE users SET settings=settings-'family' WHERE id=90102")
    before = Accounts.settings(c.member.id)

    assert {:error, :invalid_input} =
             Families.set_sharing(scope(c.member), %{"enabled" => true, "duration" => []}, opts())

    assert Accounts.settings(c.member.id) == before

    assert {:ok, 500, {:object, fields}} =
             legacy_sharing(c.member, %{"enabled" => true, "duration" => []})

    refute Map.new(fields)["success"]
    assert Accounts.settings(c.member.id)["family"]["location_sharing"]["enabled"]
    Repo.query!("UPDATE users SET settings=jsonb_set(settings,'{family}', '[]') WHERE id=90102")
    assert locations(c.owner).status == 500
  end

  defp legacy_sharing(user, attrs) do
    user =
      Accounts.get(user.id)
      |> Map.put(:timezone, "Europe/Berlin")
      |> Map.put(:locale, attrs["locale"] || "en")

    Families.SharingUpdate.web_call(user, attrs, @now)
  end

  defp locations(user) do
    Plug.Test.conn("GET", "/family/locations.json")
    |> Plug.Conn.assign(:current_user, user)
    |> Plug.Conn.assign(:now, @now)
    |> Plug.Conn.assign(:self_hosted, true)
    |> FamilyLocations.call([])
  end
end
