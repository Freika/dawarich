defmodule Dawarich.ImportExportIndexTest do
  use ExUnit.Case, async: false

  alias Dawarich.ImportExportIndex
  alias Dawarich.Test.ImportsExportsSeeds, as: Seeds

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)

    %{
      user: Seeds.user!(7301, %{"timezone" => "Europe/Berlin"}),
      other: Seeds.user!(7302, %{"timezone" => "UTC"})
    }
  end

  defp list(fun, user, column \\ "created_at", direction \\ :desc, page \\ 1),
    do: apply(ImportExportIndex, fun, [user, %{column: column, direction: direction, page: page}])

  defp ids(result), do: Enum.map(result.entries, & &1.id)

  defp at(hours_ago), do: NaiveDateTime.add(~N[2026-09-26 12:00:00], -hours_ago * 3600)

  test "lists only the user's own imports and exports", %{user: user, other: other} do
    Seeds.import!(%{id: 730_101, user_id: user.id, created_at: at(2)})
    Seeds.import!(%{id: 730_102, user_id: user.id, created_at: at(1)})
    Seeds.import!(%{id: 730_201, user_id: other.id, created_at: at(0)})
    Seeds.export!(%{id: 730_151, user_id: user.id})
    Seeds.export!(%{id: 730_251, user_id: other.id})

    assert ids(list(:imports, user)) == [730_102, 730_101]
    assert ids(list(:exports, user)) == [730_151]
  end

  test "reads the record's own original file, never a prepared download or another table's attachment",
       %{user: user} do
    Seeds.import!(%{id: 730_111, user_id: user.id, created_at: at(2)})
    Seeds.file!("Import", 730_111, "file", 900_001, 2048, "a.gpx")
    Seeds.import!(%{id: 730_112, user_id: user.id, created_at: at(1)})
    Seeds.file!("Import", 730_112, "prepared_download", 900_002, 4096, "b.zip")
    Seeds.file!("Export", 730_112, "file", 900_003, 8192, "c.zip")
    Seeds.export!(%{id: 730_161, user_id: user.id, created_at: at(2)})
    Seeds.file!("Import", 730_161, "file", 900_004, 16, "d.gpx")
    Seeds.export!(%{id: 730_163, user_id: user.id, created_at: at(1)})
    Seeds.file!("Export", 730_163, "file", 900_006, 64, "f.json.zip")

    assert Map.new(list(:imports, user).entries, &{&1.id, &1.byte_size}) ==
             %{730_111 => 2048, 730_112 => nil}

    assert Enum.map(list(:exports, user).entries, &{&1.id, &1.blob_id, &1.filename, &1.byte_size}) ==
             [{730_163, 900_006, "f.json.zip", 64}, {730_161, nil, nil, nil}]
  end

  test "sorting by file size keeps only rows with a file, on the page and in the page count",
       %{user: user} do
    for n <- 1..25 do
      Seeds.import!(%{id: 731_000 + n, user_id: user.id, created_at: at(n)})
      Seeds.file!("Import", 731_000 + n, "file", 910_000 + n, n * 10, "#{n}.gpx")
    end

    Seeds.import!(%{id: 731_100, user_id: user.id, created_at: at(0)})

    assert list(:imports, user).total_pages == 2
    by_size = list(:imports, user, "byte_size", :asc)
    assert {by_size.total_pages, hd(by_size.entries).id} == {1, 731_001}
    refute 731_100 in ids(by_size)
  end

  test "sorts each column both ways with Postgres' null placement, as Rails' ORDER BY does",
       %{user: user} do
    for {id, name, status, processed, hours} <- [
          {732_001, "C", 0, 30, 6},
          {732_002, "A", 1, 10, 5},
          {732_003, "E", 2, 50, 7},
          {732_004, "B", 3, nil, 4},
          {732_005, "D", 4, 20, 8}
        ] do
      Seeds.import!(%{
        id: id,
        user_id: user.id,
        name: name,
        status: status,
        processed: processed,
        created_at: at(hours)
      })
    end

    assert ids(list(:imports, user)) == [732_004, 732_002, 732_001, 732_003, 732_005]

    assert ids(list(:imports, user, "created_at", :asc)) == [
             732_005,
             732_003,
             732_001,
             732_002,
             732_004
           ]

    assert ids(list(:imports, user, "name", :asc)) == [
             732_002,
             732_004,
             732_001,
             732_005,
             732_003
           ]

    assert ids(list(:imports, user, "processed", :asc)) == [
             732_002,
             732_005,
             732_001,
             732_003,
             732_004
           ]

    assert ids(list(:imports, user, "processed", :desc)) == [
             732_004,
             732_003,
             732_001,
             732_005,
             732_002
           ]

    assert ids(list(:imports, user, "status", :desc)) == [
             732_005,
             732_004,
             732_003,
             732_002,
             732_001
           ]
  end

  test "pages by 25 and counts pages over all the user's rows", %{user: user} do
    for n <- 1..27, do: Seeds.export!(%{id: 733_000 + n, user_id: user.id, created_at: at(n)})

    first = list(:exports, user)
    assert {length(first.entries), first.total_pages, hd(first.entries).id} == {25, 2, 733_001}
    assert ids(list(:exports, user, "created_at", :desc, 2)) == [733_026, 733_027]
    assert list(:exports, user, "created_at", :desc, 3).entries == []
  end

  test "the created time comes back in the user's zone, with Rails' UTC marker only for UTC zones",
       %{user: user} do
    previous = System.get_env("TIME_ZONE")
    System.put_env("TIME_ZONE", "Asia/Tokyo")

    on_exit(fn ->
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    cases = [
      {user, ~N[2026-09-20 12:00:00], 7200, false},
      {Seeds.user!(7303, %{"timezone" => "UTC"}), ~N[2026-09-20 10:00:00], 0, true},
      {Seeds.user!(7304, %{"timezone" => "Etc/GMT"}), ~N[2026-09-20 10:00:00], 0, false},
      {Seeds.user!(7305, %{"timezone" => "Mars/Olympus"}), ~N[2026-09-20 19:00:00], 32_400,
       false},
      {Seeds.user!(7306, %{}), ~N[2026-09-20 19:00:00], 32_400, false}
    ]

    for {{owner, local, offset, utc}, n} <- Enum.with_index(cases) do
      Seeds.import!(%{id: 734_000 + n, user_id: owner.id, created_at: ~N[2026-09-20 10:00:00]})
      [%{created: created}] = list(:imports, owner).entries
      assert NaiveDateTime.compare(created.local, local) == :eq, inspect(owner.settings)
      assert {created.offset, created.utc} == {offset, utc}, inspect(owner.settings)
    end
  end

  test "maps Rails' enums; an integer outside an enum reads as nil", %{user: user} do
    Seeds.import!(%{
      id: 735_001,
      user_id: user.id,
      source: 15,
      status: 4,
      additional_data_extraction_status: 5,
      created_at: at(1)
    })

    Seeds.import!(%{
      id: 735_002,
      user_id: user.id,
      source: nil,
      status: 0,
      additional_data_extraction_status: 2,
      created_at: at(2)
    })

    Seeds.import!(%{id: 735_003, user_id: user.id, source: 99, status: 3, created_at: at(3)})
    Seeds.export!(%{id: 735_051, user_id: user.id, file_format: nil, file_type: 1, status: 1})

    assert Enum.map(list(:imports, user).entries, &{&1.source, &1.status, &1.extraction}) == [
             {"mobile_photo_library", "deleting", "unsupported"},
             {nil, "created", "running"},
             {nil, "failed", "not_attempted"}
           ]

    assert [%{file_format: nil, file_type: "user_data", status: "processing"}] =
             list(:exports, user).entries
  end
end
