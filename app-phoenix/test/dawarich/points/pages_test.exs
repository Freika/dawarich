defmodule Dawarich.Points.PagesTest do
  use ExUnit.Case, async: false
  alias Dawarich.Accounts.Scope
  alias Dawarich.Points.Pages
  alias Dawarich.{Repo, Accounts}
  alias Dawarich.Test.{FrameSeeds, NativeAdminUI}

  @now ~U[2026-03-31 10:00:00Z]
  @params %{"start_at" => "1772359200", "end_at" => "1772362200", "order_by" => "ASC"}

  setup do
    %{target: user, actor: foreign} = NativeAdminUI.setup!()
    %{scope: Scope.for_user(user, "de"), foreign: foreign}
  end

  test "point filters are normalized once and retain inclusive owner bounds", %{
    scope: scope,
    foreign: foreign
  } do
    for index <- 0..50,
        do: FrameSeeds.point!(scope.user.id, 120_000 + index, 1_772_359_200 + index * 60)

    FrameSeeds.point!(foreign.id, 130_000, 1_772_359_200)
    assert {:ok, page} = Pages.load(scope, @params, now: @now, self_hosted: true)
    assert page.query["order_by"] == "asc"
    assert {page.count, length(page.rows), page.total_pages} == {51, 50, 2}
    assert Enum.map(page.rows, & &1.id) == Enum.to_list(120_000..120_049)

    assert {:ok, second} =
             Pages.load(scope, Map.put(@params, "page", "2tail"), now: @now, self_hosted: true)

    assert Enum.map(second.rows, & &1.id) == [120_050]

    assert {:ok, outside} =
             Pages.load(scope, Map.put(@params, "page", "3"), now: @now, self_hosted: true)

    assert outside.rows == []
    assert {:ok, address} = Pages.address(scope, "120000")
    assert address.id == 120_000
    assert {:error, :not_found} = Pages.address(scope, "130000")
  end

  test "point selection cannot admit a foreign or outside-window id", %{
    scope: scope,
    foreign: foreign
  } do
    FrameSeeds.point!(scope.user.id, 120_001, 1_772_359_200)
    FrameSeeds.point!(scope.user.id, 120_002, 1_772_362_201)
    FrameSeeds.point!(foreign.id, 130_001, 1_772_359_200)
    opts = [now: @now, self_hosted: true]
    assert {:ok, [120_001]} = Pages.selection(scope, @params, ["120001"], opts)
    assert {:error, :unauthorized} = Pages.selection(scope, @params, ["130001"], opts)
    assert {:error, :unauthorized} = Pages.selection(scope, @params, ["120002"], opts)
    assert {:error, :limit} = Pages.selection(scope, @params, List.duplicate("120001", 51), opts)
    assert {:ok, []} = Pages.selection(scope, @params, [""], opts)
  end

  test "selected import survives a bounded option search", %{scope: scope, foreign: foreign} do
    stamp = ~N[2026-03-01 00:00:00]

    for i <- 1..61,
        do:
          Repo.insert_all("imports", [
            %{
              id: 140_000 + i,
              user_id: scope.user.id,
              name: "Import #{i}",
              created_at: NaiveDateTime.add(stamp, i),
              updated_at: stamp
            }
          ])

    Repo.insert_all("imports", [
      %{id: 150_000, user_id: foreign.id, name: "Foreign", created_at: stamp, updated_at: stamp}
    ])

    assert {:ok, page} =
             Pages.load(scope, %{"import_id" => "140001", "import_search" => "61"},
               now: @now,
               self_hosted: true
             )

    assert Enum.sort(Enum.map(page.imports, & &1.id)) == [140_001, 140_061]

    assert {:ok, all} =
             Pages.load(scope, %{"import_id" => "140001"}, now: @now, self_hosted: true)

    assert length(all.imports) == 50
    assert Enum.any?(all.imports, &(&1.id == 140_001))

    assert {:error, :not_found} =
             Pages.load(scope, %{"import_id" => "150000"}, now: @now, self_hosted: true)
  end

  test "point read has constant query count and discards raw provider metadata", %{scope: scope} do
    FrameSeeds.point!(scope.user.id, 120_001, 1_772_359_200, %{
      geodata: %{
        "properties" => %{
          "street" => "Synthetic Street",
          "api_key" => "synthetic-provider-capability"
        }
      }
    })

    Repo.query!(
      "UPDATE points SET geodata=$1 WHERE id=$2",
      [
        %{
          "properties" => %{
            "street" => "Synthetic Street",
            "api_key" => "synthetic-provider-capability"
          }
        },
        120_001
      ],
      log: false
    )

    assert {:ok, _} = Pages.load(scope, @params, now: @now, self_hosted: true)

    {{:ok, one}, first} =
      NativeAdminUI.queries(fn -> Pages.load(scope, @params, now: @now, self_hosted: true) end)

    for i <- 2..50, do: FrameSeeds.point!(scope.user.id, 120_000 + i, 1_772_359_200 + i * 60)

    {{:ok, page}, full} =
      NativeAdminUI.queries(fn -> Pages.load(scope, @params, now: @now, self_hosted: true) end)

    assert length(page.rows) == 50
    assert length(full) == length(first)
    assert hd(one.rows).geodata["properties"]["street"] == "Synthetic Street"
    refute :erlang.term_to_binary(page) =~ "synthetic-provider-capability"
  end

  test "positive and negative import overflow refuse before queries or effects", %{scope: scope} do
    before_counts =
      Repo.query!(
        "SELECT (SELECT count(*) FROM points), (SELECT count(*) FROM imports), (SELECT count(*) FROM oban.oban_jobs)",
        [],
        log: false
      ).rows

    for value <- ["9223372036854775808", "-9223372036854775809"] do
      params = Map.put(@params, "import_id", value)
      assert {:error, :invalid_input} = Pages.normalize(params)

      {result, queries} =
        NativeAdminUI.queries(fn -> Pages.load(scope, params, now: @now, self_hosted: true) end)

      assert result == {:error, :invalid_input}
      refute Enum.any?(queries, &String.contains?(&1, "FROM public.imports"))

      assert {:error, :invalid_input} =
               Pages.selection(scope, params, [], now: @now, self_hosted: true)
    end

    assert Repo.query!(
             "SELECT (SELECT count(*) FROM points), (SELECT count(*) FROM imports), (SELECT count(*) FROM oban.oban_jobs)",
             [],
             log: false
           ).rows == before_counts

    for value <- ["9223372036854775807", "-9223372036854775808", "", "1tail"] do
      assert {:ok, _, ""} = Pages.normalize(Map.put(@params, "import_id", value))
    end
  end

  test "malformed point filters and changed identity refuse before a projection", %{scope: scope} do
    for params <- [
          %{"page" => []},
          %{"start_at" => %{}},
          %{"order_by" => "DROP"},
          %{"page" => String.duplicate("9", 128)}
        ] do
      assert {:error, :invalid_input} = Pages.load(scope, params, now: @now, self_hosted: true)
    end

    assert {:ok, page} =
             Pages.load(scope, %{"start_at" => "0", "end_at" => "99999999999"},
               now: @now,
               self_hosted: true
             )

    assert page.window.start == "1970-01-01T00:00:00Z"

    Repo.query!(
      "UPDATE users SET encrypted_password='new-identity-00000000000000000000' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} = Pages.load(scope, @params, now: @now, self_hosted: true)
    refute is_nil(Accounts.get(scope.user.id))
  end
end
