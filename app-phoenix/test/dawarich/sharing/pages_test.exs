defmodule Dawarich.Sharing.PagesTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Test.{RailsUser, StatsSeeds, FrameSeeds, NativePublicAdmission}
  @now ~U[2026-10-10 10:00:00Z]

  setup do
    RailsUser.insert!(%{
      id: 18901,
      email: "native-public@example.invalid",
      api_key: "synthetic-private-key",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    rows(
      "INSERT INTO trips(id,user_id,name,started_at,ended_at,distance,created_at,updated_at) VALUES(18901,18901,'Synthetic public trip','2026-01-01','2026-03-12',12000,now(),now())"
    )

    uuid = Ecto.UUID.generate()

    rows(
      "INSERT INTO shared_links(id,user_id,resource_type,resource_id,name,settings,created_at,updated_at) VALUES($1::text::uuid,18901,0,18901,'Synthetic link',$2,now(),now())",
      [uuid, %{"show_days" => true, "show_photos" => false}]
    )

    %{grant: %{id: uuid}}
  end

  test "public cached projection refuses revoked expired and deleted resources", %{grant: grant} do
    assert {:ok, page} = resource(grant)
    warm = [reader: fn _, _ -> {:ok, page} end]
    rows("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [grant.id])
    assert {:error, :not_found} = resource(grant, %{}, warm)

    rows("UPDATE shared_links SET revoked_at=NULL,expires_at=$2 WHERE id=$1::text::uuid", [
      grant.id,
      DateTime.to_naive(@now)
    ])

    assert {:error, :not_found} = resource(grant, %{}, warm)
    rows("UPDATE shared_links SET expires_at=NULL WHERE id=$1::text::uuid", [grant.id])
    rows("DELETE FROM trips WHERE id=18901")
    assert {:ok, %{kind: :missing_resource, resource: nil}} = resource(grant, %{}, warm)
  end

  test "public login-locked owner remains visible while deleted owner refuses" do
    uuid = Ecto.UUID.generate()
    settings = %{"enabled" => true, "expiration" => nil}

    StatsSeeds.digest!(18901, %{
      year: 2024,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: settings
    })

    StatsSeeds.stat!(18901, %{
      year: 2024,
      month: 3,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: settings
    })

    rows("UPDATE users SET locked_at=now() WHERE id=18901")

    for kind <- [:digest, :month] do
      assert {:ok, page} = apply(Dawarich.Sharing.Pages, :report, [kind, uuid, [now: @now]])
      refute inspect(page) =~ "synthetic-private-key"
      refute Map.has_key?(page, :user)
    end

    rows("UPDATE users SET deleted_at=now() WHERE id=18901")

    for kind <- [:digest, :month],
        do:
          assert(
            {:error, :not_found} ==
              apply(Dawarich.Sharing.Pages, :report, [kind, uuid, [now: @now]])
          )
  end

  test "shared description and photos obey share privacy flags", %{grant: grant} do
    rows(
      "INSERT INTO action_text_rich_texts(record_type,record_id,name,body,created_at,updated_at) VALUES('Trip',18901,'description',$1,now(),now())",
      [
        "<p onclick='unsafe()'>Allowed <a href='javascript:unsafe()'>link</a></p><script>unsafe()</script>"
      ]
    )

    opts = [photos: fn _ -> {:ok, Enum.map(1..101, &{:object, [{"id", &1}]})} end]
    assert {:ok, page} = resource(grant, %{}, opts)
    assert page.resource.description =~ "Allowed"
    refute page.resource.description =~ "javascript:"
    refute page.resource.description =~ "onclick"
    assert page.resource.photos == []

    rows("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      grant.id,
      %{"show_description" => false, "show_days" => false, "show_photos" => true}
    ])

    assert {:ok, hidden} = resource(grant, %{}, opts)
    assert hidden.resource.description == nil
    assert hidden.resource.days == []
    assert length(hidden.resource.photos) == 100

    rows(
      "INSERT INTO notes(user_id,attachable_type,attachable_id,noted_at,body,created_at,updated_at) VALUES(18901,'Trip',18901,'2026-01-20 12:00:00','Visible day note',now(),now())"
    )

    rows("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      grant.id,
      %{"show_days" => true, "show_day_notes" => true}
    ])

    assert {:ok, notes} = resource(grant)
    assert Enum.find(notes.resource.days, &(&1.date == ~D[2026-01-20])).note == "Visible day note"

    rows("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [
      grant.id,
      %{"show_days" => true, "show_day_notes" => false}
    ])

    assert {:ok, private_notes} = resource(grant)
    assert Enum.all?(private_notes.resource.days, &is_nil(&1.note))
  end

  test "shared day pages stay bounded without omitting private filtering", %{grant: grant} do
    for day <- 0..39 do
      at = DateTime.to_unix(~U[2026-01-01 10:00:00Z]) + day * 86400
      FrameSeeds.point!(18901, 189_100 + day, at)
    end

    FrameSeeds.place!(18901, 18901, "Hidden")
    FrameSeeds.tag!(18901, 18901, "Private", 18901, ~N[2026-01-01 00:00:00])
    rows("UPDATE tags SET privacy_radius_meters=1000 WHERE id=18901")
    assert {:ok, first} = resource(grant)
    assert length(first.resource.days) == 31
    assert Enum.all?(first.resource.days, &is_nil(&1.stats))
    assert first.resource.next_cursor == "2026-02-01"
    assert {:ok, second} = resource(grant, %{"cursor" => first.resource.next_cursor})
    assert hd(second.resource.days).date == ~D[2026-02-01]

    assert MapSet.disjoint?(
             MapSet.new(first.resource.days, & &1.date),
             MapSet.new(second.resource.days, & &1.date)
           )

    assert {:error, :invalid_input} = resource(grant, %{"cursor" => []})
    assert {:error, :invalid_input} = resource(grant, %{"cursor" => "2025-01-01"})
  end

  test "public delivery repeats grant and privacy admission after a ready read", %{grant: grant} do
    reader = fn link, params ->
      result = apply(Dawarich.Sharing.ResourceWindow, :load, [link, params, []])
      rows("UPDATE shared_links SET revoked_at=now() WHERE id=$1::text::uuid", [grant.id])
      result
    end

    assert {:error, :not_found} = resource(grant, %{}, reader: reader)
    rows("UPDATE shared_links SET revoked_at=NULL WHERE id=$1::text::uuid", [grant.id])

    reader = fn link, params ->
      result = apply(Dawarich.Sharing.ResourceWindow, :load, [link, params, []])
      FrameSeeds.place!(18901, 18901, "Hidden")
      FrameSeeds.tag!(18901, 18901, "Private", 18901, ~N[2026-01-01 00:00:00])
      rows("UPDATE tags SET privacy_radius_meters=1000 WHERE id=18901")
      result
    end

    assert {:error, :not_found} = resource(grant, %{}, reader: reader)
  end

  test "public report delivery rechecks sharing settings and current owner" do
    uuid = Ecto.UUID.generate()
    settings = %{"enabled" => true, "expiration" => nil}

    StatsSeeds.digest!(18901, %{
      year: 2024,
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: settings
    })

    hook = fn -> rows("UPDATE digests SET sharing_settings='{}'::jsonb WHERE user_id=18901") end

    assert {:error, :not_found} =
             apply(Dawarich.Sharing.Pages, :report, [:digest, uuid, [now: @now, after_read: hook]])
  end

  test "public track projection retains source duration elevation and mode behind stats visibility",
       %{grant: grant} do
    FrameSeeds.track!(18901, 18901, %{
      start_at: ~N[2026-01-01 10:00:00],
      end_at: ~N[2026-01-01 11:00:00],
      distance: 12000,
      duration: 3600,
      avg_speed: 12.0,
      elevation_gain: 50,
      elevation_loss: 20,
      dominant_mode: 2
    })

    rows("UPDATE shared_links SET resource_type=1,settings=$2 WHERE id=$1::text::uuid", [
      grant.id,
      %{"show_stats" => true}
    ])

    assert {:ok, page} = resource(grant)
    assert page.resource.unit == "km"

    assert {page.resource.track_duration, page.resource.speed, page.resource.gain,
            page.resource.loss, page.resource.mode} == {3600, 12.0, 50.0, 20.0, 2}

    rows("UPDATE shared_links SET settings='{}'::jsonb WHERE id=$1::text::uuid", [grant.id])
    assert {:ok, hidden} = resource(grant)
    assert hidden.resource.speed == nil
    assert hidden.resource.distance == nil
  end

  test "public report place windows keep complete totals without unbounded city payloads" do
    uuid = Ecto.UUID.generate()

    places =
      for n <- 1..51, do: StatsSeeds.toponym("Country #{n}", for(c <- 1..7, do: "City #{n}-#{c}"))

    share = %{
      sharing_uuid: Ecto.UUID.dump!(uuid),
      sharing_settings: %{"enabled" => true, "expiration" => nil}
    }

    StatsSeeds.digest!(18901, Map.merge(share, %{year: 2024, toponyms: places}))
    StatsSeeds.stat!(18901, Map.merge(share, %{year: 2024, month: 3, toponyms: places}))

    assert {:ok, digest} =
             Dawarich.Sharing.Pages.report(:digest, uuid, now: @now, self_hosted: true)

    assert digest.totals.countries == 51
    assert digest.totals.cities == 357
    assert length(digest.digest.toponyms) == 50
    assert digest.more

    assert {:ok, rest} =
             Dawarich.Sharing.Pages.report(:digest, uuid, now: @now, self_hosted: true, page: "2")

    assert length(rest.digest.toponyms) == 1
    assert {:ok, month} = Dawarich.Sharing.Pages.report(:month, uuid, now: @now)
    assert length(month.stat.toponyms) == 50
    assert Enum.all?(month.stat.toponyms, &(length(&1["cities"]) == 5))
    assert month.totals == %{countries: 51, cities: 357}
  end

  defp resource(grant, params \\ %{}, opts \\ []),
    do:
      apply(Dawarich.Sharing.Pages, :resource, [
        grant,
        params,
        Keyword.merge([now: @now, admission: NativePublicAdmission], opts)
      ])
end
