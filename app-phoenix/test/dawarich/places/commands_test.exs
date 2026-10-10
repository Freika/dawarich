defmodule Dawarich.Places.CommandsTest do
  use ExUnit.Case, async: true
  alias Dawarich.{Places, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.FrameSeeds, as: S
  @attrs %{"name" => "New", "latitude" => "51.12345678", "longitude" => "12.12345678"}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    actor = S.user!(11831)
    other = S.user!(11832)
    S.place!(actor.id, 118_301, "Before")
    S.place!(other.id, 118_302, "Foreign tagged")
    S.tag!(actor.id, 118_311, "Own", 118_301, ~N[2026-01-01 00:00:00])
    S.tag!(other.id, 118_312, "Foreign", 118_302, ~N[2026-01-01 00:00:00])
    S.tag!(actor.id, 118_313, "Second own", 118_302, ~N[2026-01-01 00:00:00])
    %{scope: Scope.for_user(actor, "en"), other: other}
  end

  defp row(id),
    do:
      Repo.query!(
        "SELECT name,latitude::float8,longitude::float8,source,note,name_locked_at,demo FROM places WHERE id=$1",
        [id]
      ).rows

  defp tags(id),
    do:
      Repo.query!(
        "SELECT tag_id FROM taggings WHERE taggable_type='Place' AND taggable_id=$1 ORDER BY tag_id",
        [id]
      ).rows
      |> List.flatten()

  test "native Place saves preserve precision source locks adoption and tag omission", ctx do
    assert {:ok, %{id: id}} = apply(Places, :create, [ctx.scope, @attrs])
    assert [["New", 51.123457, 12.123457, 0, nil, lock, false]] = row(id)
    assert lock != nil

    assert {:ok, %{id: suggested}} =
             apply(Places, :create, [ctx.scope, %{@attrs | "name" => "Suggested place"}])

    assert [[_, _, _, _, _, nil, _]] = row(suggested)
    Repo.query!("UPDATE places SET source=1,demo=true WHERE id=118301", [])
    before = row(118_301)

    assert {:ok, %{id: 118_301}} =
             apply(Places, :update, [ctx.scope, 118_301, %{"note" => "Only note"}])

    assert [["Before", lat, lon, 1, "Only note", nil, false]] = row(118_301)
    assert [lat, lon] == Enum.slice(hd(before), 1, 2)
    assert tags(118_301) == [118_311]

    assert {:ok, _} =
             apply(Places, :update, [ctx.scope, 118_301, %{"tag_ids" => ["118312", "118311"]}])

    assert tags(118_301) == [118_311]
    assert {:ok, _} = apply(Places, :update, [ctx.scope, 118_301, %{"tag_ids" => []}])
    assert tags(118_301) == []

    for {source, expected} <- [{"gpx_waypoint", 2}, {nil, nil}, {"manual", 0}] do
      assert {:ok, _} = apply(Places, :update, [ctx.scope, id, %{"source" => source}])
      assert Enum.at(hd(row(id)), 3) == expected
    end
  end

  test "native tag-phase failure returns saved identity without inviting duplicate create", ctx do
    assert {:partial, %{id: id}, :tags_failed} =
             apply(Places, :create, [
               ctx.scope,
               Map.put(@attrs, "tag_ids", ["118311"]),
               [repo: Dawarich.Test.PlacesTagFailureRepo]
             ])

    assert [["New", _, _, _, _, _, _]] = row(id)
    assert tags(id) == []
    Repo.query!("UPDATE places SET demo=true WHERE id=118301", [])

    assert {:partial, %{id: 118_301}, :tags_failed} =
             apply(Places, :update, [
               ctx.scope,
               118_301,
               %{"name" => "Saved", "tag_ids" => ["118313"]},
               [repo: Dawarich.Test.PlacesTagFailureRepo]
             ])

    assert [["Saved", _, _, _, _, _, false]] = row(118_301)
    assert tags(118_301) == [118_311]
  end

  test "native Place deletion preserves visits and unrelated graph", ctx do
    S.visit!(ctx.scope.user.id, 118_321, %{
      place_id: 118_301,
      started_at: ~N[2026-01-01 08:00:00],
      ended_at: ~N[2026-01-01 08:30:00]
    })

    assert apply(Places, :delete, [ctx.scope, 118_301]) == {:ok, 118_301}
    assert Repo.query!("SELECT place_id FROM visits WHERE id=118321", []).rows == [[nil]]
    assert row(118_301) == []
    assert tags(118_301) == []
    assert Repo.query!("SELECT id FROM tags WHERE id=118311", []).rows == [[118_311]]
    S.place!(ctx.scope.user.id, 118_303, "Rich")

    Repo.insert_all("action_text_rich_texts", [
      %{
        id: 118_333,
        name: "note",
        record_type: "Place",
        record_id: 118_303,
        body: "Rich",
        created_at: ~N[2026-01-01 00:00:00],
        updated_at: ~N[2026-01-01 00:00:00]
      }
    ])

    assert apply(Places, :delete, [ctx.scope, 118_303]) == {:error, :unsupported}
    assert row(118_303) != []
  end

  test "foreign Place suggestions fence update and delete with an unchanged graph", ctx do
    S.visit!(ctx.other.id, 118_321, %{
      started_at: ~N[2026-01-01 08:00:00],
      ended_at: ~N[2026-01-01 08:30:00]
    })

    S.suggest!(118_331, 118_321, 118_301)
    assert_foreign_graph_fenced(ctx)
  end

  test "foreign Place taggings fence update and delete with an unchanged graph", ctx do
    S.tag!(ctx.other.id, 118_314, "Foreign attached", 118_301, ~N[2026-01-01 00:00:00])
    assert_foreign_graph_fenced(ctx)
  end

  test "foreign Place notes fence update and delete with an unchanged graph", ctx do
    Repo.insert_all("notes", [
      %{
        id: 118_341,
        user_id: ctx.other.id,
        attachable_type: "Place",
        attachable_id: 118_301,
        title: "Foreign note",
        body: "Retain foreign body",
        noted_at: ~N[2026-01-01 00:00:00],
        created_at: ~N[2026-01-01 00:00:00],
        updated_at: ~N[2026-01-01 00:00:00]
      }
    ])

    assert_foreign_graph_fenced(ctx)
  end

  defp assert_foreign_graph_fenced(ctx) do
    before = dependent_graph()

    assert Places.update(ctx.scope, 118_301, %{
             "name" => "Forbidden",
             "note" => "Forbidden",
             "tag_ids" => []
           }) ==
             {:error, :foreign_dependents}

    assert dependent_graph() == before
    assert Places.delete(ctx.scope, 118_301) == {:error, :foreign_dependents}
    assert dependent_graph() == before
  end

  defp dependent_graph do
    Map.new(
      [
        {"places", "id,user_id,name,note,latitude,longitude,source,demo,updated_at"},
        {"visits", "id,user_id,place_id,name,status,updated_at"},
        {"place_visits", "id,visit_id,place_id,created_at,updated_at"},
        {"tags", "id,user_id,name,updated_at"},
        {"taggings", "id,tag_id,taggable_id,taggable_type,created_at,updated_at"},
        {"notes", "id,user_id,attachable_id,attachable_type,title,body,noted_at,updated_at"}
      ],
      fn {table, fields} ->
        {table,
         Repo.query!(
           "SELECT #{fields} FROM #{table} WHERE id BETWEEN 118300 AND 118399 ORDER BY id",
           [],
           log: false
         ).rows}
      end
    )
  end

  test "native Place commands refuse stale actors and foreign dependents before effects", ctx do
    S.visit!(ctx.other.id, 118_321, %{
      place_id: 118_301,
      started_at: ~N[2026-01-01 08:00:00],
      ended_at: ~N[2026-01-01 08:30:00]
    })

    before = row(118_301)

    assert apply(Places, :update, [ctx.scope, 118_301, %{"name" => "Forbidden"}]) ==
             {:error, :foreign_dependents}

    assert apply(Places, :delete, [ctx.scope, 118_301]) == {:error, :foreign_dependents}
    assert row(118_301) == before
    assert Repo.query!("SELECT place_id FROM visits WHERE id=118321", []).rows == [[118_301]]
    S.place!(ctx.scope.user.id, 118_303, "Clean")

    assert apply(Places, :update, [
             ctx.scope,
             118_303,
             %{"name" => "Revoked"},
             [repo: Dawarich.Test.PlacesRevokingRepo]
           ]) == {:error, :stale_session}

    assert hd(hd(row(118_303))) == "Clean"
    assert apply(Places, :create, [ctx.scope, @attrs]) == {:error, :stale_session}
    assert apply(Places, :update, [ctx.scope, ctx.other.id, @attrs]) == {:error, :stale_session}
  end
end
