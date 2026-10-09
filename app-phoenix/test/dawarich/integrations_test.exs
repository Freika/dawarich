defmodule Dawarich.IntegrationsTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Integrations, Repo, UserSettings, UserTimeZone}
  alias Dawarich.Test.RailsUser

  @corpus "test/fixtures/settings_corpus.json" |> File.read!() |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    user =
      RailsUser.insert!(%{
        id: 5391,
        email: "a5s3-int@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: user}
  end

  defp source(user, id, attrs) do
    stamp = ~N[2026-09-20 10:00:00]

    Repo.insert_all("trip_sources", [
      Map.merge(
        %{
          id: id,
          user_id: user.id,
          provider: "trek",
          base_url: "https://trek-#{id}.a5s3.test",
          status: 0,
          importing: false,
          created_at: stamp,
          updated_at: stamp
        },
        attrs
      )
    ])
  end

  test "ActiveModel boolean casting, the legacy digest key and the default-on flags" do
    assert Enum.map(
             [
               nil,
               "",
               false,
               0,
               "0",
               "f",
               "F",
               "false",
               "FALSE",
               "off",
               "OFF",
               "yes",
               1,
               0.0,
               true
             ],
             &UserSettings.cast/1
           ) ==
             [
               nil,
               nil,
               false,
               false,
               false,
               false,
               false,
               false,
               false,
               false,
               false,
               true,
               true,
               true,
               true
             ]

    legacy = %{settings: %{"digest_emails_enabled" => "false"}}
    refute UserSettings.digest?(legacy, "monthly_digest_emails_enabled")
    assert UserSettings.digest?(%{settings: %{}}, "yearly_digest_emails_enabled")

    assert UserSettings.digest?(
             %{
               settings: %{
                 "digest_emails_enabled" => false,
                 "monthly_digest_emails_enabled" => "1"
               }
             },
             "monthly_digest_emails_enabled"
           )

    assert UserSettings.on_unless_off?(%{settings: %{}}, "news_emails_enabled")

    refute UserSettings.on_unless_off?(
             %{settings: %{"news_emails_enabled" => ""}},
             "news_emails_enabled"
           )

    assert UserSettings.get(%{settings: ["not", "an", "object"]}) == ["not", "an", "object"]
  end

  test "statuses follow Integrations::Status: URL and key, TeslaMate URL only, TREK by an active source",
       %{user: user} do
    user = %{
      user
      | settings: %{
          "immich_url" => "https://immich.a5s3.test",
          "immich_api_key" => "a5s3-k-1",
          "immich_connection_status" => "ok",
          "photoprism_url" => "https://photo.a5s3.test",
          "photoprism_api_key" => " ",
          "photoprism_connection_status" => "ok",
          "airtrail_url" => "https://air.a5s3.test",
          "airtrail_api_key" => "a5s3-k-2",
          "airtrail_connection_status" => "failed",
          "teslamate_url" => "https://tesla.a5s3.test",
          "teslamate_connection_status" => "ok"
        }
    }

    source(user, 53_901, %{status: 1})

    assert Integrations.statuses(user, Integrations.trek_sources(user)) ==
             %{
               "immich" => "connected",
               "photoprism" => nil,
               "airtrail" => "failed",
               "teslamate" => "connected",
               "trek" => nil
             }

    source(user, 53_902, %{created_at: ~N[2026-09-21 10:00:00]})
    assert Integrations.statuses(user, Integrations.trek_sources(user))["trek"] == "connected"
  end

  test "TREK sources in creation order, with Rails' enum names and local sync times", %{
    user: user
  } do
    source(user, 53_903, %{
      created_at: ~N[2026-09-22 10:00:00],
      status: 1,
      last_error: "TREK answered 401"
    })

    source(user, 53_904, %{
      created_at: ~N[2026-09-21 10:00:00],
      last_synced_at: ~N[2026-09-25 10:15:00]
    })

    source(user, 53_905, %{created_at: ~N[2026-09-23 10:00:00], status: 7})

    assert [
             %{id: 53_904, status: "active", active: true, synced: ~N[2026-09-25 12:15:00]},
             %{
               id: 53_903,
               status: "disabled",
               active: false,
               last_error: "TREK answered 401",
               synced: nil
             },
             %{id: 53_905, status: nil, active: false}
           ] = Integrations.trek_sources(user)
  end

  test "last-synced text matches Rails' Time.zone.parse + l(:long), raw when Rails cannot parse" do
    for %{"value" => value, "zone" => zone, "output" => output} <- @corpus["times"] do
      user = %{settings: %{"timezone" => zone, "airtrail_last_synced_at" => value}}

      assert Integrations.synced_text("en", user, "airtrail_last_synced_at") == (output || value),
             value
    end

    assert Integrations.synced_text("en", %{settings: %{}}, "airtrail_last_synced_at") == nil

    assert Integrations.synced_text(
             "en",
             %{settings: %{"airtrail_last_synced_at" => " "}},
             "airtrail_last_synced_at"
           ) == nil
  end

  test "UserTimeZone.local gives A7's zoned map" do
    assert %{local: ~N[2026-09-25 12:15:00], offset: 7200, utc: false} =
             UserTimeZone.local(%{"timezone" => "Europe/Berlin"}, ~N[2026-09-25 10:15:00])

    assert %{local: ~N[2026-09-25 10:15:00], offset: 0, utc: true} =
             UserTimeZone.local(%{"timezone" => "UTC"}, ~N[2026-09-25 10:15:00])
  end

  test "users inspect without settings or API key" do
    user = %Dawarich.Accounts.User{
      settings: %{"immich_api_key" => "a5s3-k-inspect"},
      api_key: "a5s3-k-api"
    }

    refute inspect(user) =~ "a5s3-k-"
  end

  test "the service parameter falls back to Immich" do
    assert Integrations.service("trek") == "trek"
    assert Integrations.service("geocoding") == "immich"
    assert Integrations.service(["trek"]) == "immich"
  end

  describe "scope writes" do
    setup %{user: user} do
      previous = System.get_env("SELF_HOSTED")
      System.put_env("SELF_HOSTED", "true")

      on_exit(fn ->
        if previous,
          do: System.put_env("SELF_HOSTED", previous),
          else: System.delete_env("SELF_HOSTED")
      end)

      %{
        scope: Dawarich.Accounts.Scope.for_user(Dawarich.Accounts.get(user.id), "en"),
        url: Dawarich.Test.NativeIntegrationStub.start!()
      }
    end

    test "credentials save every provider, preserve sentinels and URL-only edits, and replace new secrets",
         %{scope: scope, url: url} do
      for provider <- ~w(immich photoprism airtrail teslamate) do
        secret =
          if provider == "teslamate", do: "teslamate_password", else: provider <> "_api_key"

        assert {:ok, %{success: true, alerts: []}} =
                 Integrations.update_credentials(scope, provider, %{
                   (provider <> "_url") => url,
                   secret => "synthetic-first"
                 })

        assert {:ok, _} =
                 Integrations.update_credentials(scope, provider, %{secret => "********"})

        assert Dawarich.Accounts.settings(scope.user.id)[secret] == "synthetic-first"

        assert {:ok, _} =
                 Integrations.update_credentials(scope, provider, %{
                   (provider <> "_url") => url <> "/"
                 })

        assert Dawarich.Accounts.settings(scope.user.id)[secret] == "synthetic-first"

        assert {:ok, _} =
                 Integrations.update_credentials(scope, provider, %{secret => "synthetic-new"})

        assert Dawarich.Accounts.settings(scope.user.id)[secret] == "synthetic-new"
      end
    end

    test "credential failures keep Rails alerts and expired or Lite accounts cannot write", %{
      scope: scope,
      url: url
    } do
      assert {:ok, %{alerts: [alert]}} =
               Integrations.update_credentials(scope, "immich", %{
                 "immich_url" => url <> "/fail",
                 "immich_api_key" => "synthetic"
               })

      assert alert ==
               DawarichWeb.Translate.t(
                 "en",
                 "services.immich.connection_tester.immich_connection_failed_code",
                 %{code: 401}
               )

      Repo.query!("UPDATE users SET active_until=now()-interval '1 day' WHERE id=$1", [
        scope.user.id
      ])

      assert {:error, :inactive} =
               Integrations.update_credentials(scope, "immich", %{"immich_api_key" => "blocked"})

      Repo.query!("UPDATE users SET active_until='3026-01-01',plan=0 WHERE id=$1", [scope.user.id])

      System.put_env("SELF_HOSTED", "false")

      assert {:error, :pro_required} =
               Integrations.update_credentials(scope, "immich", %{"immich_api_key" => "blocked"})

      refute Dawarich.Accounts.settings(scope.user.id)["immich_api_key"] == "blocked"
    end

    test "sync writes publish the existing durable AirTrail and TeslaMate jobs without a credential check",
         %{scope: scope} do
      for {service, kind} <- [
            {:airtrail, "imports.airtrail_flights"},
            {:teslamate, "imports.teslamate_sync"}
          ] do
        Dawarich.Jobs.Ownership.put!(Repo, "command:" <> kind, :oban)
        assert {:ok, :queued} = Integrations.start_sync(scope, service)

        assert Repo.query!(
                 "SELECT payload FROM job_outbox WHERE command_type=$1 AND aggregate_id=$2",
                 [kind, scope.user.id]
               ).rows == [[%{"user_id" => scope.user.id}]]
      end
    end

    test "photo cache refresh removes only this user's entries", %{scope: scope} do
      start_supervised!(
        {Redix, {System.fetch_env!("PHOENIX_TEST_REDIS_URL"), [name: Dawarich.Redis.Cache]}}
      )

      own = "photos_#{scope.user.id}_native_probe"
      other = "photos_999999_native_probe"
      Dawarich.Redis.cache_command(["SET", own, "synthetic"])
      Dawarich.Redis.cache_command(["SET", other, "synthetic"])
      on_exit(fn -> Dawarich.Redis.cache_command(["DEL", own, other]) end)
      assert :ok = Integrations.refresh_photos_cache(scope)
      assert {:ok, nil} = Dawarich.Redis.cache_command(["GET", own])
      assert {:ok, "synthetic"} = Dawarich.Redis.cache_command(["GET", other])
    end
  end
end
