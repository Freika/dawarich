defmodule DawarichWeb.A12f3bReviewR4Test do
  use Dawarich.JobsCase, async: false
  import Dawarich.Test.FamilyCorpus
  alias Dawarich.{Accounts, Repo, Families}

  setup do: seed()

  @tag a12f3b_review: "R4"
  test "native R4 consent preserves URL normalization across web and API writes", c do
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
    assert {:ok, _} = Families.set_sharing(scope(c.member), %{"enabled" => false}, opts())
    settings = Accounts.settings(c.member.id)
    assert settings["family"]["location_sharing"] == %{"enabled" => false}
    assert settings["immich_url"] == "https://photos.example.test"
    assert settings["photoprism_url"] == "https://gallery.example.test"
    assert settings["maps"] == %{"url" => "https://maps.example.test/", "other" => "preserved"}

    Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [
      Map.put(settings, "immich_url", "https://photos.example.test/")
    ])

    assert {:ok, _} = Families.set_sharing(scope(c.member), %{"enabled" => false}, opts())

    assert Accounts.settings(c.member.id)["immich_url"] == "https://photos.example.test"

    for dirty <- [
          %{"immich_url" => "https://photos.example.test/"},
          %{"photoprism_url" => "https://gallery.example.test/"},
          %{"maps" => %{"url" => " https://maps.example.test/ "}}
        ] do
      stored = Map.merge(settings, dirty)
      Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [stored])
      api_user = Map.put(Accounts.get(c.member.id), :timezone, "Europe/Berlin")

      for params <- [%{"enabled" => false}, %{"enabled" => false, "web" => true}] do
        assert {:ok, 200, body} =
                 DawarichWeb.Api.FamilyController.run(
                   :sharing,
                   api_user,
                   params,
                   ~U[2026-10-03 10:00:00Z]
                 )

        assert body
               |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
               |> IO.iodata_to_binary()
               |> Jason.decode!() == %{
                 "success" => true,
                 "enabled" => false,
                 "duration" => "permanent",
                 "message" => "Location sharing disabled"
               }

        normalized = Accounts.settings(c.member.id)
        assert normalized["immich_url"] == "https://photos.example.test"
        assert normalized["photoprism_url"] == "https://gallery.example.test"
        assert normalized["maps"]["url"] == "https://maps.example.test/"
      end

      assert {:ok, _} = Families.set_sharing(scope(c.member), %{"enabled" => false}, opts())
    end

    for malformed <- [
          %{"immich_url" => []},
          %{"maps" => []},
          %{"maps" => %{"url" => 1}},
          %{"family" => []}
        ] do
      Repo.query!("UPDATE users SET settings=$1 WHERE id=90102", [Map.merge(settings, malformed)])
      before = Accounts.settings(c.member.id)

      assert {:error, _} = Families.set_sharing(scope(c.member), %{"enabled" => false}, opts())

      assert Accounts.settings(c.member.id) == before
    end
  end
end
