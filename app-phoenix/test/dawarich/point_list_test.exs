defmodule Dawarich.PointListTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Accounts, PointList, PointListWindow, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}

  @now ~U[2026-03-31 10:00:00Z]
  @berlin %{"timezone" => "Europe/Berlin", "maps" => %{"distance_unit" => "km"}}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  defp user(id, settings \\ @berlin, plan \\ 1) do
    RailsUser.insert!(%{
      id: id,
      email: "a6s3-p1-#{id}@example.invalid",
      settings: settings,
      plan: plan
    })

    Accounts.get(id)
  end

  defp point(user, id, at, attrs \\ %{}),
    do: FrameSeeds.point!(user.id, id, DateTime.to_unix(at), attrs)

  defp import!(user, id, stamp \\ "2026-03-01T10:00:00") do
    Repo.insert_all("imports", [
      %{
        id: id,
        user_id: user.id,
        name: "Synthetic #{id}.json",
        created_at: NaiveDateTime.from_iso8601!(stamp),
        updated_at: NaiveDateTime.from_iso8601!(stamp)
      }
    ])
  end

  defp load(user, params \\ %{}, now \\ @now, hosted \\ true),
    do: PointList.load(user, params, now, self_hosted: hosted, env: %{})

  test "default month begins on the calendar month shift" do
    window = PointListWindow.build(%{}, @berlin, @now, nil)
    assert window.start == "2026-02-28T00:00:00+01:00"
    assert window.end == "2026-03-31T23:59:59+02:00"
    assert window.start_epoch == DateTime.to_unix(~U[2026-02-27 23:00:00Z])
  end

  test "import bounds precede plan filtering" do
    owner = user(8361, @berlin, 0)
    import!(owner, 83611)
    point(owner, 836_101, ~U[2024-01-01 10:00:00Z])
    point(owner, 836_102, ~U[2026-03-01 10:00:00Z])
    Repo.query!("UPDATE points SET import_id = $1 WHERE user_id = $2", [83611, owner.id])

    assert {:ok, page} = load(owner, %{"import_id" => "83611"}, @now, false)
    assert page.window.start == "2024-01-01T00:00:00+01:00"
    assert page.window.end == "2026-03-01T23:59:59+01:00"
    assert Enum.map(page.rows, & &1.id) == [836_102]
    assert [%{id: 83611, name: "Synthetic 83611.json"}] = page.imports
    other = user(8362)
    import!(other, 83612)
    assert :rails = load(owner, %{"import_id" => "83612"})
  end

  test "list is owner scoped inclusive and fifty per page" do
    owner = user(8363)
    foreign = user(8364)
    first = ~U[2026-03-01 10:00:00Z]
    for i <- 0..50, do: point(owner, 836_301 + i, DateTime.add(first, i * 60))
    point(foreign, 836_499, DateTime.add(first, 1))
    params = %{"start_at" => "1772359200", "end_at" => "1772362200", "order_by" => "asc"}

    assert {:ok, page} = load(owner, params)
    assert {page.count, page.page, page.total_pages} == {51, 1, 2}
    assert Enum.map(page.rows, & &1.id) == Enum.to_list(836_301..836_350)
    assert {:ok, second} = load(owner, Map.put(params, "page", "2abc"))
    assert Enum.map(second.rows, & &1.id) == [836_351]
    assert {:ok, empty} = load(owner, Map.put(params, "page", "3"))
    assert {empty.rows, empty.count, empty.total_pages} == {[], 51, 2}
    refute Map.has_key?(hd(page.rows), :raw_data)
    assert {:ok, descending} = load(owner, Map.put(params, "order_by", "DESC"))
    assert hd(descending.rows).id == 836_351
  end

  test "Lite cutoff uses twelve calendar months and full access bypasses it" do
    owner = user(8365, @berlin, 0)
    point(owner, 836_501, ~U[2023-02-28 09:59:59Z])
    point(owner, 836_502, ~U[2023-02-28 10:00:00Z])
    params = %{"start_at" => "2023-02-28T00:00:00Z", "end_at" => "2023-03-01T00:00:00Z"}
    assert {:ok, lite} = load(owner, params, ~U[2024-02-29 10:00:00Z], false)
    assert Enum.map(lite.rows, & &1.id) == [836_502]
    assert {:ok, hosted} = load(owner, params, ~U[2024-02-29 10:00:00Z])
    assert length(hosted.rows) == 2
    assert {:ok, pro} = load(%{owner | plan: 1}, params, ~U[2024-02-29 10:00:00Z], false)
    assert length(pro.rows) == 2

    point(owner, 836_503, ~U[2025-03-29 10:59:59Z])
    point(owner, 836_504, ~U[2025-03-29 11:00:00Z])
    dst_params = %{"start_at" => "2025-03-29T00:00:00Z", "end_at" => "2025-03-30T00:00:00Z"}
    assert {:ok, dst} = load(owner, dst_params, ~U[2026-03-29 10:00:00Z], false)
    assert Enum.map(dst.rows, & &1.id) == [836_504]

    family_owner = user(8366, @berlin, 2)
    stamp = ~N[2026-03-31 10:00:00]

    Repo.insert_all("families", [
      %{
        id: 83651,
        name: "Synthetic",
        creator_id: family_owner.id,
        created_at: stamp,
        updated_at: stamp
      }
    ])

    Repo.insert_all("family_memberships", [
      %{family_id: 83651, user_id: owner.id, role: 1, created_at: stamp, updated_at: stamp}
    ])

    assert {:ok, family} = load(owner, params, ~U[2024-02-29 10:00:00Z], false)
    assert length(family.rows) == 2
  end

  test "nonexact ordering and unsupported settings request Rails" do
    owner = user(8367)
    point(owner, 836_701, ~U[2026-03-01 10:00:00Z])

    Repo.query!("UPDATE points SET lonlat = ST_GeogFromText('POINT(12.4 51.4)') WHERE id = $1", [
      836_701
    ])

    point(owner, 836_702, ~U[2026-03-01 10:00:00Z])
    assert :rails = load(owner)
    Repo.query!("DELETE FROM points WHERE id = $1", [836_702])
    assert {:ok, _} = load(owner)
    import!(owner, 83671)
    import!(owner, 83672)
    assert :rails = load(owner)
    Repo.query!("DELETE FROM imports WHERE id = $1", [83672])
    assert :rails = load(%{owner | settings: %{"timezone" => "Unknown/Zone"}})
    assert :rails = load(%{owner | settings: %{"maps" => []}})
    assert :rails = load(%{owner | settings: %{"timezone" => 123}})
    assert :rails = load(owner, %{"order_by" => "timestamp desc"})
    assert :rails = load(owner, %{"page" => "99999999999999999999999"})
    assert :rails = load(owner, %{"start_at" => ["2026-03-01"]})
  end

  test "supported explicit timestamps reuse map parsing without map defaults" do
    default = PointListWindow.build(%{"start_at" => "", "end_at" => " "}, @berlin, @now, nil)
    assert default.start == "2026-02-28T00:00:00+01:00"

    bounded =
      PointListWindow.build(%{"start_at" => "0", "end_at" => "99999999999"}, @berlin, @now, nil)

    assert {bounded.start, bounded.end} ==
             {"1970-01-01T01:00:00+01:00", "2100-01-01T00:00:00+01:00"}

    offset =
      PointListWindow.build(%{"start_at" => "2026-03-01T00:00:00+05:00"}, @berlin, @now, nil)

    assert offset.start == "2026-02-28T20:00:00+01:00"

    range =
      {DateTime.to_unix(~U[2025-01-01 22:00:00Z]), DateTime.to_unix(~U[2025-01-03 22:00:00Z])}

    imported = PointListWindow.build(%{}, @berlin, @now, range)

    assert {imported.start, imported.end} ==
             {"2025-01-01T00:00:00+01:00", "2025-01-03T23:59:59+01:00"}
  end
end
