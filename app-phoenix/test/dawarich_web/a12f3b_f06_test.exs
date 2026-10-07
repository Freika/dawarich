defmodule DawarichWeb.A12f3bF06Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.{Accounts, Repo}
  alias DawarichWeb.FamilyLocations
  setup do: seed()
  @now ~U[2026-10-03 10:00:00Z]

  @tag a12f3b_case: "F06a"
  test "family location sharing preserves duration and member audience", c do
    conn =
      json_request(c.member, "PATCH", "/family/location_sharing", %{
        "enabled" => "on",
        "duration" => "2"
      })

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["duration"] == "2"
    config = Accounts.settings(c.member.id)["family"]["location_sharing"]
    assert config["enabled"]
    assert config["expires_at"] == "2026-10-03T14:00:00+02:00"

    assert json_request(c.member, "PATCH", "/family/location_sharing", %{
             "enabled" => %{"nested" => false},
             "duration" => "1h",
             "share_history" => "true"
           }).status == 200

    assert Accounts.settings(c.member.id)["family"]["location_sharing"]["share_history"]

    localized =
      json_request(c.member, "PATCH", "/family/location_sharing", %{
        "enabled" => true,
        "duration" => "1h",
        "locale" => "de"
      })

    localized_fields = Jason.decode!(localized.resp_body)

    assert localized_fields["message"] ==
             DawarichWeb.Translate.t(
               "de",
               "services.families.update_location_sharing.enabled_for_hours",
               %{"count" => 1}
             )

    assert localized_fields["expires_at_formatted"] ==
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

    refused =
      request(c.outsider, "PATCH", "/family/location_sharing", %{"enabled" => true}, [
        {"accept", "text/vnd.turbo-stream.html"}
      ])

    assert refused.status == 404
    assert refused.resp_body =~ ~s(target="flash-messages")

    assert refused.resp_body =~
             DawarichWeb.Translate.t(
               "en",
               "controllers.family.location_sharing.user_is_not_part_of_a_family",
               %{}
             )

    System.put_env("SELF_HOSTED", "false")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    Repo.query!("UPDATE families SET access_until=$1 WHERE id=91001", [DateTime.to_naive(@now)])
    Repo.query!("UPDATE users SET plan=1 WHERE id=90101")

    assert json_request(c.member, "PATCH", "/family/location_sharing", %{"enabled" => false}).status ==
             200

    assert Accounts.settings(c.member.id)["family"]["location_sharing"] == %{"enabled" => false}
  end

  @tag a12f3b_case: "F06b"
  test "family sharing error stays native before and after commit", c do
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, nil)
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, previous) end)

    direct =
      Plug.Test.conn("PATCH", "/family/location_sharing")
      |> Plug.Conn.put_req_header("accept", "application/json")

    terminal =
      DawarichWeb.FamilySharingActions.respond(
        direct,
        {:ok, 500, {:object, [{"success", false}]}}
      )

    assert terminal.status == 500
    Repo.query!("UPDATE users SET settings=jsonb_set(settings,'{family}', '[]') WHERE id=90102")

    malformed =
      json_request(c.member, "PATCH", "/family/location_sharing", %{
        "enabled" => true,
        "duration" => "1h"
      })

    assert malformed.status == 500
    assert Accounts.settings(c.member.id)["family"] == []
    Repo.query!("UPDATE users SET settings=settings-'family' WHERE id=90102")

    after_write =
      json_request(c.member, "PATCH", "/family/location_sharing", %{
        "enabled" => true,
        "duration" => []
      })

    assert after_write.status == 500
    refute Jason.decode!(after_write.resp_body)["success"]
    assert Accounts.settings(c.member.id)["family"]["location_sharing"]["enabled"] == true
    refute Map.has_key?(after_write.private, :dawarich_proxy)
    Repo.query!("UPDATE users SET settings=jsonb_set(settings,'{family}', '[]') WHERE id=90102")
    failed_read = locations(c.owner)
    assert failed_read.status == 500
    refute Map.has_key?(failed_read.private, :dawarich_proxy)
  end

  defp locations(user) do
    Plug.Test.conn("GET", "/family/locations.json")
    |> Plug.Conn.assign(:current_user, user)
    |> Plug.Conn.assign(:now, @now)
    |> Plug.Conn.assign(:self_hosted, true)
    |> FamilyLocations.call([])
  end
end
