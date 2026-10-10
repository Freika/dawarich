defmodule Dawarich.Trips.PagesTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.{NativeAdminUI, TripsSeeds}
  alias Dawarich.Trips.Pages

  @now ~U[2026-10-03 10:00:00Z]
  @path [[12.5, 51.25], [12.373468123456789, 51.34]]

  defp scope(id, settings \\ %{"timezone" => "Europe/Berlin"}) do
    TripsSeeds.user!(id, settings)
    Scope.for_user(Accounts.get(id), "en")
  end

  defp trip!(scope, id, attrs),
    do: TripsSeeds.trip!(Map.merge(%{id: id, user_id: scope.user.id}, attrs))

  defp located_stay!(trip_id),
    do:
      Dawarich.Test.SeedIds.insert_all!(Repo, "planned_accommodations", [
        %{
          trip_id: trip_id,
          name: "Pension",
          latitude: 51.3,
          longitude: 12.4,
          created_at: ~N[2026-01-01 00:00:00],
          updated_at: ~N[2026-01-01 00:00:00]
        }
      ])

  defp list!(scope, params \\ %{}) do
    {:ok, result} = Pages.list(scope, params, @now)
    result
  end

  test "six trip cards have constant query count rather than one plan load per card" do
    one = scope(9_501)
    six = scope(9_502)
    located_stay!(trip!(one, 950_101, %{path: nil}))

    for n <- 1..6 do
      id =
        trip!(six, 950_200 + n, %{
          path: if(rem(n, 2) == 0, do: @path),
          started_at: NaiveDateTime.add(~N[2026-01-01 08:00:00], n * 86_400),
          ended_at: NaiveDateTime.add(~N[2026-01-02 08:00:00], n * 86_400)
        })

      located_stay!(id)
    end

    list!(one)
    {single, one_queries} = NativeAdminUI.queries(fn -> list!(one) end)
    {page, six_queries} = NativeAdminUI.queries(fn -> list!(six) end)

    assert length(single.entries) == 1
    assert length(page.entries) == 6
    assert length(six_queries) == length(one_queries)
    assert Enum.map(single.entries, & &1.preview) == [:plan]

    assert Enum.map(page.entries, & &1.preview) ==
             [:path, :plan, :path, :plan, :path, :plan]
  end

  test "a foreign plan source never marks a card as planned" do
    owner = scope(9_503)
    stranger = scope(9_504)
    TripsSeeds.trip_source!(95_041, stranger.user.id)
    id = trip!(owner, 950_301, %{path: nil, trip_source_id: 95_041})
    located_stay!(id)

    assert [%{preview: :no_points}] = list!(owner).entries
    assert {:ok, %{plan: nil}} = Pages.get(owner, id, @now)
  end

  test "family cards disappear after consent is withdrawn" do
    owner = scope(9_505)
    viewer = scope(9_506)

    [[family]] =
      Repo.query!(
        "INSERT INTO families(name,creator_id,created_at,updated_at) VALUES('Synthetic family',$1,now(),now()) RETURNING id",
        [owner.user.id]
      ).rows

    for user <- [owner.user, viewer.user],
        do:
          Repo.query!(
            "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
            [family, user.id]
          )

    trip!(owner, 950_501, %{
      started_at: ~N[2026-05-09 23:30:00],
      ended_at: ~N[2026-05-11 22:30:00]
    })

    Repo.query!(
      "INSERT INTO shared_links(name,resource_type,resource_id,user_id,settings,created_at,updated_at) VALUES('Family',0,$1,$2,$3,now(),now())",
      [950_501, owner.user.id, %{"audience" => "family", "family_id" => family}]
    )

    System.put_env("SELF_HOSTED", "true")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)

    assert [%{name: "trip 950501", started_on: ~D[2026-05-10], ended_on: ~D[2026-05-12]}] =
             list!(viewer).family_entries

    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [owner.user.id])

    assert list!(viewer).family_entries == []
    assert list!(viewer).family_total_pages == 0
  end

  test "trip detail state keeps no map paths provider settings or api key" do
    owner =
      scope(9_507, %{
        "timezone" => "Europe/Berlin",
        "immich_url" => "https://photos.example.invalid",
        "immich_api_key" => "synthetic-provider-key"
      })

    id = trip!(owner, 950_701, %{path: @path})
    TripsSeeds.rich_text!(id, "<div>Plain notes</div>")

    assert {:ok, detail} = Pages.get(owner, id, @now)
    dump = inspect(detail, limit: :infinity, printable_limit: :infinity)

    refute dump =~ "synthetic-provider-key"
    refute dump =~ owner.user.api_key
    refute dump =~ "12.37346"
    refute dump =~ "photos.example.invalid"

    for key <- [:path_json, :api_key, :windows_json, :studio, :plan_json, :photos],
        do: refute(Map.has_key?(detail, key))

    assert detail.description =~ ~s(<div class="trix-content">)
    assert detail.description =~ "<div>Plain notes</div>"
    assert detail.settings == %{unit: "km", factor: 1000, photos: true}
  end

  test "trip detail keeps owner-local dates, duration, sorted string countries and refuses foreign ids" do
    owner = scope(9_508)
    stranger = scope(9_509)

    id =
      trip!(owner, 950_801, %{
        visited_countries: ["France", 7, "Germany"],
        started_at: ~N[2026-05-09 06:00:00],
        ended_at: ~N[2026-05-12 20:00:00]
      })

    assert {:ok, detail} = Pages.get(owner, id, @now)
    assert detail.countries == ["France", "Germany"]
    assert {detail.first_day, detail.last_day} == {~D[2026-05-09], ~D[2026-05-12]}
    assert NaiveDateTime.compare(detail.started_at.local, ~N[2026-05-09 08:00:00]) == :eq
    assert detail.duration == [{"days", 3}, {"hours", 14}]
    assert detail.description == nil
    refute detail.future_start

    assert Pages.get(stranger, id, @now) == {:error, :not_found}
    assert Pages.get(owner, "950801x", @now) == {:error, :not_found}
    assert Pages.get(owner, ["950801"], @now) == {:error, :not_found}
    assert Pages.days(stranger, id, nil) == {:error, :not_found}
  end

  test "malformed countries count only their names and unsupported settings refuse typed" do
    owner = scope(9_510)
    trip!(owner, 951_001, %{visited_countries: ["France", %{"x" => 1}], path: nil, distance: 0})
    assert [%{countries: 1, preview: :no_points}] = list!(owner).entries

    odd = scope(9_511, %{"maps" => %{"distance_unit" => "parsecs"}})
    assert Pages.list(odd, %{}, @now) == {:error, :unsupported}
    assert Pages.get(odd, 1, @now) == {:error, :unsupported}
  end

  test "page parameters normalize once with source casts and bounded overflow" do
    assert Pages.normalize(%{"page" => "2abc", "family_page" => "-3"}) ==
             %{page: 2, family_page: 1}

    assert Pages.normalize(%{"page" => ["2"], "family_page" => %{"a" => "1"}}) ==
             %{page: 1, family_page: 1}

    assert Pages.normalize(%{"page" => String.duplicate("9", 40)}).page == 1_000_000_000_000
    assert Pages.normalize("x") == %{page: 1, family_page: 1}

    owner = scope(9_512)

    for n <- 1..7,
        do:
          trip!(owner, 951_200 + n, %{
            started_at: NaiveDateTime.add(~N[2025-06-01 08:00:00], n * 86_400),
            ended_at: NaiveDateTime.add(~N[2025-06-01 18:00:00], n * 86_400)
          })

    first = list!(owner)
    assert Enum.map(first.entries, & &1.id) == Enum.map(7..2//-1, &(951_200 + &1))
    assert first.total_pages == 2
    assert Enum.map(list!(owner, %{"page" => "2"}).entries, & &1.id) == [951_201]
    assert list!(owner, %{"page" => String.duplicate("9", 40)}).entries == []
  end

  test "day windows stay bounded, continue by cursor and carry their dated notes" do
    owner = scope(9_513)

    id =
      trip!(owner, 951_301, %{
        started_at: ~N[2026-03-01 08:00:00],
        ended_at: ~N[2026-04-09 18:00:00]
      })

    TripsSeeds.note!(%{
      id: 951_391,
      trip_id: id,
      user_id: owner.user.id,
      body: "Day thirty-five",
      noted_at: ~N[2026-04-04 12:00:00]
    })

    assert {:ok, first} = Pages.days(owner, id, nil)
    assert length(first.days) == 31
    assert hd(first.days).date == ~D[2026-03-01]
    assert first.next == ~D[2026-04-01]
    assert Enum.all?(first.days, &is_nil(&1.note))

    assert {:ok, rest} = Pages.days(owner, id, first.next)

    assert Enum.map(rest.days, & &1.date) ==
             Enum.to_list(Date.range(~D[2026-04-01], ~D[2026-04-09]))

    assert rest.next == nil
    assert Enum.find(rest.days, &(&1.date == ~D[2026-04-04])).note.body == "Day thirty-five"
  end
end
