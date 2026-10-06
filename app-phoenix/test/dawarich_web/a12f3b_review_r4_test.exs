defmodule DawarichWeb.A12f3bReviewR4Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyForms
  alias Dawarich.{Accounts, Repo}

  setup do: seed()

  @tag a12f3b_review: "R4"
  test "R4 disabling sharing applies successful Rails URL normalization", c do
    settings = Accounts.settings(c.member.id)

    settings =
      settings
      |> Map.put("immich_url", "https://photos.example.test///")
      |> Map.put("photoprism_url", "https://gallery.example.test/")
      |> Map.put("maps", %{"url" => " \thttps://maps.example.test/ \n", "other" => "preserved"})
      |> Map.put("family", %{
        "location_sharing" => %{"enabled" => true, "duration" => "permanent"}
      })

    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [settings])
    conn = json_request(c.member, "PATCH", "/family/location_sharing", %{"enabled" => false})
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["success"]
    settings = Accounts.settings(c.member.id)
    assert settings["family"]["location_sharing"] == %{"enabled" => false}
    assert settings["immich_url"] == "https://photos.example.test"
    assert settings["photoprism_url"] == "https://gallery.example.test"
    assert settings["maps"] == %{"url" => "https://maps.example.test/", "other" => "preserved"}

    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [
      Map.put(settings, "immich_url", "https://photos.example.test/")
    ])

    assert json_request(c.member, "PATCH", "/family/location_sharing", %{"enabled" => false}).status ==
             200

    assert Accounts.settings(c.member.id)["immich_url"] == "https://photos.example.test"

    for malformed <- [
          %{"immich_url" => []},
          %{"maps" => []},
          %{"maps" => %{"url" => 1}},
          %{"family" => []}
        ] do
      Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [Map.merge(settings, malformed)])
      before = Accounts.settings(c.member.id)

      assert json_request(c.member, "PATCH", "/family/location_sharing", %{"enabled" => false}).status ==
               500

      assert Accounts.settings(c.member.id) == before
    end
  end
end
