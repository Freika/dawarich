defmodule DawarichWeb.NativeTripMapTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  alias Dawarich.{Accounts, Maps, Repo}
  alias Dawarich.Test.{RailsUser, TripsSeeds}
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-09-29 12:00:00Z]
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    TripsSeeds.user!(8841, %{"timezone" => "UTC"})
    TripsSeeds.user!(8899, %{"timezone" => "UTC"})

    TripsSeeds.trip!(%{
      id: 884_101,
      user_id: 8841,
      path: [[12.37, 51.338], [12.381, 51.341]],
      started_at: ~N[2026-06-01 22:00:00],
      ended_at: ~N[2026-06-03 01:00:00]
    })

    %{user: Accounts.get(8841)}
  end

  test "trip map list uses M5 normalized bounded cards", ctx do
    scope = Maps.principal(ctx.user, "en")
    assert {:ok, result} = Dawarich.Maps.Trip.list(scope, -1, -1, now: @now)
    assert result.query == %{page: 1, family_page: 1}
    assert [%{id: 884_101, preview: :path}] = result.entries
    refute Map.has_key?(hd(result.entries), :path_json)
  end

  test "native trip map admits only the owned trip and excludes bulk state", ctx do
    scope = Maps.principal(ctx.user, "en")
    assert {:ok, metadata} = Dawarich.Maps.Trip.config(scope, 884_101, now: @now)
    assert metadata["tripId"] == 884_101
    assert metadata["range"]["startAt"] == "2026-06-01T22:00:00Z"
    refute Map.has_key?(metadata, "path")
    refute Map.has_key?(metadata, "api_key")

    assert {:error, :not_found} =
             Dawarich.Maps.Trip.config(
               Maps.principal(Accounts.get(8899), "en"),
               884_101,
               now: @now
             )

    conn =
      RailsUser.signed_in(ctx.user.id)
      |> Plug.Conn.assign(:now, @now)
      |> get("/native/map/data/trips/884101")

    assert conn.status == 200
    data = json_response(conn, 200)
    assert data["path"] == [[12.37, 51.338], [12.381, 51.341]]
    assert data["deviceWindows"] == []
    refute conn.resp_body =~ "api_key"
    assert (RailsUser.signed_in(8899) |> get("/native/map/data/trips/884101")).status == 404
  end

  test "native trip presentation retains source countries days and notes without bulk or credential state",
       ctx do
    TripsSeeds.note!(%{
      id: 884_110,
      trip_id: 884_101,
      user_id: 8841,
      body: "Coffee <b>outside</b>",
      noted_at: ~N[2026-06-02 12:00:00]
    })

    scope = Maps.principal(ctx.user, "en")
    assert {:ok, page} = Dawarich.Maps.Trip.presentation(scope, 884_101, now: @now)
    assert page.id == 884_101
    assert Enum.map(page.days, & &1.date) == [~D[2026-06-01], ~D[2026-06-02], ~D[2026-06-03]]
    assert page.day_notes[~D[2026-06-02]].body == "Coffee <b>outside</b>"
    assert page.settings.unit == "km"

    refute Enum.any?(
             [:api_key, :path_json, :windows_json, :plan_json, :trip_stream, :studio],
             &Map.has_key?(page, &1)
           )

    assert {:error, :not_found} =
             Dawarich.Maps.Trip.presentation(
               Maps.principal(Accounts.get(8899), "en"),
               884_101,
               now: @now
             )
  end

  test "native trip presentation replaces key-bearing photo URLs with cookie thumbnail reads",
       ctx do
    assert {:ok, page} = Dawarich.TripPage.load(ctx.user, 884_101, @now)

    photo = %{
      id: "synthetic/photo",
      source: "immich",
      url: "/api/v1/photos/id?api_key=synthetic-private",
      taken_at: "2026-06-02T12:00:00Z",
      orientation: "portrait"
    }

    [first | rest] = page.days
    page = %{page | days: [%{first | photos: [photo]} | rest]}
    safe = Dawarich.Maps.Trip.present(page)

    assert hd(hd(safe.days).photos).url ==
             "/native/map/data/photos/synthetic%2Fphoto/thumbnail?source=immich"

    refute String.contains?(inspect(safe), "synthetic-private")
    refute Map.has_key?(safe.photos, :photos)
    refute Map.has_key?(safe.photos, :previews)
  end

  test "native trip presentation keeps ordinary photo source navigation and refuses credential-bearing links",
       ctx do
    assert {:ok, page} = Dawarich.TripPage.load(ctx.user, 884_101, @now)

    for bad <- [
          "https://user:synthetic-private@photos.test/library",
          "https://photos.test/library?api_key=synthetic-private"
        ] do
      photos = %{
        page.photos
        | sources: ["immich", "photoprism"],
          links: %{"immich" => "https://photos.test/search", "photoprism" => bad}
      }

      safe = Dawarich.Maps.Trip.present(%{page | photos: photos})
      assert safe.photos.links == %{"immich" => "https://photos.test/search"}
      assert safe.photos.sources == ["immich"]
      refute String.contains?(inspect(safe), "synthetic-private")
    end
  end

  test "native trip presentation excludes private itinerary source credentials while keeping ordinary navigation",
       ctx do
    assert {:ok, page} = Dawarich.TripPage.load(ctx.user, 884_101, @now)

    for url <- [
          "https://user:synthetic-private@trek.test",
          "https://trek.test?token=synthetic-private"
        ] do
      source = %{id: 1, provider: "trek", base_url: url, status: 0, last_synced_at: nil}

      safe =
        Dawarich.Maps.Trip.present(%{page | plan: %{page.plan | source: source}})

      assert safe.plan.source == nil
      refute String.contains?(inspect(safe), "synthetic-private")
    end

    source = %{
      id: 1,
      provider: "trek",
      base_url: "https://trek.test",
      status: 0,
      last_synced_at: nil
    }

    safe = Dawarich.Maps.Trip.present(%{page | plan: %{page.plan | source: source}})
    assert safe.plan.source == source
  end

  test "trip map adapter refuses the original revoked session", ctx do
    scope = Maps.principal(ctx.user, "en")

    Repo.query!("UPDATE users SET encrypted_password = 'synthetic-revoked' WHERE id = $1", [
      ctx.user.id
    ])

    assert {:error, :stale_session} =
             Dawarich.Maps.Trip.config(scope, 884_101, now: @now)
  end
end
