defmodule DawarichWeb.NativePublicCapabilityTest do
  use ExUnit.Case, async: true
  import Plug.Test
  alias Dawarich.{Accounts, Repo, RailsCookies}
  alias Dawarich.Test.TripsSeeds
  alias DawarichWeb.SharedLinkCookie
  alias Dawarich.Maps.Dependencies.Public
  @id "a1300000-0000-4000-8000-000000000001"
  @now ~U[2026-10-10 12:00:00Z]
  @secret "synthetic-public-cookie-secret"
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    TripsSeeds.user!(881_301, %{
      "timezone" => "Europe/Berlin",
      "immich_api_key" => "synthetic-provider"
    })

    TripsSeeds.trip!(%{
      id: 8_813_011,
      user_id: 881_301,
      path: [[13, 52], [14, 53]],
      started_at: ~N[2026-10-08 00:00:00],
      ended_at: ~N[2026-10-09 00:00:00]
    })

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        user_id: 881_301,
        resource_type: 0,
        resource_id: 8_813_011,
        name: "Public trip",
        magic_phrase: "synthetic-phrase",
        settings: %{"show_photos" => false},
        created_at: ~N[2026-10-09 00:00:00],
        updated_at: ~N[2026-10-09 00:00:00]
      }
    ])

    :ok
  end

  defp grant(expiry \\ DateTime.add(@now, 60)) do
    token = SharedLinkCookie.unlock_token(@id, "synthetic-phrase")
    cookie = RailsCookies.encrypt(token, "shared_link_#{@id}", @secret, expiry)
    conn = conn(:get, "/s/#{@id}") |> put_req_cookie("shared_link_#{@id}", cookie)
    proof = SharedLinkCookie.proofs(conn, @now, @secret)[@id]
    %{id: @id, proof: proof, viewer_scope: nil}
  end

  test "public capability projection excludes phrase cookie owner credentials and bulk geometry" do
    capability = grant()
    assert {:ok, config} = Public.config(capability, now: @now)
    assert config["title"] == "Public trip"
    assert config["range"]["timezone"] == "Europe/Berlin"
    assert config["photosEnabled"] == false
    text = inspect({capability, config})
    refute text =~ "synthetic-phrase"
    refute text =~ "synthetic-provider"
    refute text =~ "user_id"
    refute text =~ "path"
    refute text =~ SharedLinkCookie.unlock_token(@id, "synthetic-phrase")
  end

  test "native public trip day routing retains display thresholds" do
    assert {:ok, config} = Public.config(grant(), now: @now)
    assert config["byDay"] == true

    assert config["routeOptions"] == %{
             "distanceThresholdMeters" => 500,
             "timeThresholdMinutes" => 30
           }
  end

  test "live public location remains visible when route history is disabled" do
    Repo.query!(
      "UPDATE shared_links SET resource_type=3, resource_id=NULL, settings=$1::jsonb WHERE id=$2::text::uuid",
      [%{"show_route" => false}, @id]
    )

    TripsSeeds.point!(%{
      id: 8_813_015,
      user_id: 881_301,
      timestamp: DateTime.to_unix(@now),
      at: [13, 52]
    })

    assert {:ok, [[13.0, 52.0, _]]} = Public.read(grant(), :points, %{}, now: @now)
    assert {:ok, []} = Public.read(grant(), :route, %{}, now: @now)
  end

  test "expired revoked re-locked and deleted-owner public grants refuse every read" do
    capability = grant()
    assert {:error, :locked} = Public.config(capability, now: DateTime.add(@now, 61))

    Repo.query!(
      "UPDATE shared_links SET magic_phrase='synthetic-rotated' WHERE id=$1::text::uuid",
      [@id]
    )

    assert {:error, :locked} = Public.config(capability, now: @now)

    Repo.query!(
      "UPDATE shared_links SET magic_phrase='synthetic-phrase', revoked_at=$2 WHERE id=$1::text::uuid",
      [@id, DateTime.to_naive(@now)]
    )

    assert {:error, :not_found} = Public.read(capability, :points, %{}, now: @now)
    Repo.query!("UPDATE shared_links SET revoked_at=NULL WHERE id=$1::text::uuid", [@id])
    Repo.query!("UPDATE users SET deleted_at=$2 WHERE id=$1", [881_301, DateTime.to_naive(@now)])
    assert {:error, :not_found} = Public.config(capability, now: @now)
  end

  test "public grant refuses an unauthorized family viewer and clears fresh withdrawal" do
    TripsSeeds.user!(881_302, %{"timezone" => "UTC"})

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      @id,
      %{"audience" => "family", "family_id" => 881_303, "show_photos" => false}
    ])

    capability = %{grant() | viewer_scope: Dawarich.Maps.principal(Accounts.get(881_302), "en")}
    assert {:error, :not_found} = Public.config(capability, now: @now, self_hosted: true)
    stamp = ~N[2026-10-09 00:00:00]

    Repo.insert_all("families", [
      %{
        id: 881_303,
        creator_id: 881_301,
        name: "Native public family",
        created_at: stamp,
        updated_at: stamp
      }
    ])

    Repo.insert_all(
      "family_memberships",
      for(
        user_id <- [881_301, 881_302],
        do: %{family_id: 881_303, user_id: user_id, created_at: stamp, updated_at: stamp}
      )
    )

    assert {:ok, _} = Public.config(%{capability | proof: nil}, now: @now, self_hosted: true)
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [881_302])
    assert {:error, :not_found} = Public.config(capability, now: @now, self_hosted: true)
  end

  test "public result revoked during provider completion is dropped" do
    assert {:error, :not_found} =
             Public.read(grant(), :photos, %{},
               now: @now,
               after_read: fn ->
                 Repo.query!("UPDATE shared_links SET revoked_at=$2 WHERE id=$1::text::uuid", [
                   @id,
                   DateTime.to_naive(@now)
                 ])
               end
             )
  end

  test "public metadata exposes the exact earliest validated grant expiry" do
    assert {:ok, config} = Public.config(grant(DateTime.add(@now, 7)), now: @now)
    assert {:ok, expiry, _} = DateTime.from_iso8601(config["validUntil"])
    assert DateTime.compare(expiry, DateTime.add(@now, 7)) == :eq

    Repo.query!("UPDATE shared_links SET expires_at=$2 WHERE id=$1::text::uuid", [
      @id,
      DateTime.to_naive(DateTime.add(@now, 3))
    ])

    assert {:ok, config} = Public.config(grant(DateTime.add(@now, 7)), now: @now)
    assert {:ok, expiry, _} = DateTime.from_iso8601(config["validUntil"])
    assert DateTime.compare(expiry, DateTime.add(@now, 3)) == :eq
  end

  test "public disabled photos return empty data without provider or private read" do
    assert {:ok, []} = Public.read(grant(), :photos, %{}, now: @now)
  end

  test "Rails cookie metadata keeps the exact signed expiry and rejects expired proofs" do
    cookie = RailsCookies.encrypt("synthetic-value", "cookie", @secret, DateTime.add(@now, 7))

    assert {:ok, "synthetic-value", expiry} =
             RailsCookies.decrypt_metadata(cookie, "cookie", @secret, @now)

    assert {:ok, at, _} = DateTime.from_iso8601(expiry)
    assert DateTime.compare(at, DateTime.add(@now, 7)) == :eq

    assert :error =
             RailsCookies.decrypt_metadata(cookie, "cookie", @secret, DateTime.add(@now, 8))
  end
end
