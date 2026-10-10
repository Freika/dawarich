defmodule Dawarich.Tags.WritesTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Tags.Writes
  alias Dawarich.Test.RailsUser

  setup do
    user = RailsUser.insert!(%{id: 9194, email: "a6s4-writes@example.invalid"})
    foreign = RailsUser.insert!(%{id: 9195, email: "a6s4-writes-foreign@example.invalid"})
    ctx = %{now: ~U[2026-10-03 10:00:00.000000Z], locale: "en"}
    %{user: user, foreign: foreign, write_ctx: ctx}
  end

  defp tag!(user, id, name, attrs \\ %{}) do
    row =
      Map.merge(
        %{
          id: id,
          user_id: user.id,
          name: name,
          icon: nil,
          color: nil,
          demo: false,
          privacy_radius_meters: nil,
          created_at: ~N[2026-10-02 10:00:00.000000],
          updated_at: ~N[2026-10-02 10:00:00.000000]
        },
        attrs
      )

    Repo.insert_all("tags", [row])
    row
  end

  defp state do
    %{
      tags: Repo.query!("SELECT * FROM tags ORDER BY id").rows,
      taggings: Repo.query!("SELECT * FROM taggings ORDER BY id").rows,
      commands: commands()
    }
  end

  test "create stores actor defaults and exact submitted fields", ctx do
    tag!(ctx.foreign, 91951, "Foreign name")

    attrs = %{
      "name" => "Foreign name",
      "icon" => "☕",
      "color" => "#aBc",
      "privacy_radius_meters" => "0.5"
    }

    assert {:ok, result} = Writes.create(Repo, ctx.user, attrs, ctx.write_ctx)
    assert result.tag.user_id == ctx.user.id
    assert result.tag.name == "Foreign name"
    assert result.tag.icon == "☕"
    assert result.tag.color == "#aBc"
    assert result.tag.privacy_radius_meters == 0
    assert result.tag.demo == false
    assert result.tag.created_at == ~N[2026-10-03 10:00:00.000000]
    assert result.tag.updated_at == result.tag.created_at

    assert Repo.query!(
             "SELECT user_id,name,icon,color,privacy_radius_meters,demo FROM tags WHERE id=$1",
             [result.tag.id]
           ).rows == [[ctx.user.id, "Foreign name", "☕", "#aBc", 0, false]]

    assert {:ok, defaults} =
             Writes.create(Repo, ctx.user, %{"name" => "  Exact  "}, ctx.write_ctx)

    assert %{name: "  Exact  ", icon: nil, color: nil, privacy_radius_meters: nil, demo: false} =
             defaults.tag

    before = state()

    assert :rails =
             Writes.create(Repo, ctx.user, Map.put(attrs, "user_id", "9195"), ctx.write_ctx)

    assert state() == before
  end

  test "invalid create changes no tags taggings effects", ctx do
    tag!(ctx.user, 91941, "Existing")
    before = state()

    assert {:invalid, invalid} =
             Writes.create(Repo, ctx.user, %{"name" => "", "color" => "bad"}, ctx.write_ctx)

    assert Enum.map(invalid.errors, & &1["attribute"]) == ["name", "color"]
    assert invalid.tag.name == ""
    assert invalid.tag.color == "bad"
    assert state() == before

    assert :rails =
             Writes.create(
               Repo,
               ctx.user,
               %{"name" => "Unsupported", "privacy_radius_meters" => "1_000"},
               ctx.write_ctx
             )

    assert state() == before
  end

  test "per-owner duplicate yields invalid result and no second row", ctx do
    tag!(ctx.user, 91941, "Existing")
    before = state()

    assert {:invalid, invalid} =
             Writes.create(Repo, ctx.user, %{"name" => "Existing"}, ctx.write_ctx)

    assert Enum.map(invalid.errors, & &1["type"]) == ["taken"]
    assert state() == before
    assert {:ok, _} = Writes.create(Repo, ctx.user, %{"name" => "existing"}, ctx.write_ctx)
    assert Repo.query!("SELECT count(*) FROM tags WHERE user_id=$1", [ctx.user.id]).rows == [[2]]
    assert commands() == []
  end

  test "successful demo update adopts while failed update preserves demo", ctx do
    tag!(ctx.user, 91941, "Demo", %{
      demo: true,
      icon: "☕",
      color: "#abc",
      privacy_radius_meters: 100
    })

    before = state()

    assert {:invalid, invalid} =
             Writes.update(Repo, ctx.user, 91941, %{"name" => ""}, ctx.write_ctx)

    assert invalid.tag.demo
    assert state() == before

    assert {:ok, result} =
             Writes.update(Repo, ctx.user, 91941, %{"name" => "Adopted"}, ctx.write_ctx)

    assert %{name: "Adopted", demo: false, icon: "☕", color: "#abc", privacy_radius_meters: 100} =
             result.tag

    assert Repo.query!("SELECT name,demo,updated_at FROM tags WHERE id=91941").rows == [
             ["Adopted", false, ~N[2026-10-03 10:00:00.000000]]
           ]
  end

  test "missing foreign tag cannot mutate actor or foreign rows", ctx do
    tag!(ctx.user, 91941, "Owned")
    tag!(ctx.foreign, 91951, "Foreign", %{demo: true})
    before = state()

    for id <- [91951, 999_999] do
      assert :not_found = Writes.update(Repo, ctx.user, id, %{"name" => "Changed"}, ctx.write_ctx)
      assert :not_found = Writes.destroy(Repo, ctx.user, id)
      assert state() == before
    end

    assert {:invalid, _} = Writes.update(Repo, ctx.user, 91941, %{"name" => ""}, ctx.write_ctx)
    assert state() == before
  end

  test "delete removes all polymorphic taggings keeps resources", ctx do
    alias Dawarich.Test.FrameSeeds
    tag!(ctx.user, 91941, "Owned")
    tag!(ctx.user, 91942, "Other")
    tag!(ctx.foreign, 91951, "Foreign")
    FrameSeeds.place!(ctx.user.id, 919_401, "Synthetic place")

    FrameSeeds.visit!(ctx.user.id, 919_401, %{
      started_at: ~N[2026-10-01 10:00:00.000000],
      ended_at: ~N[2026-10-01 10:30:00.000000]
    })

    [[visit_id]] = Repo.query!("SELECT id FROM visits WHERE user_id=$1", [ctx.user.id]).rows

    for {id, tag_id, target, type} <- [
          {919_411, 91941, 919_401, "Place"},
          {919_412, 91941, visit_id, "Visit"},
          {919_413, 91941, 919_401, "Synthetic"},
          {919_414, 91942, 919_401, "Place"},
          {919_415, 91951, 919_401, "Place"}
        ] do
      Repo.insert_all("taggings", [
        %{
          id: id,
          tag_id: tag_id,
          taggable_id: target,
          taggable_type: type,
          created_at: ~N[2026-10-02 10:00:00.000000],
          updated_at: ~N[2026-10-02 10:00:00.000000]
        }
      ])
    end

    places = Repo.query!("SELECT to_jsonb(p)::text FROM places p ORDER BY id").rows
    visits = Repo.query!("SELECT * FROM visits ORDER BY id").rows

    assert {:ok, %{tag: %{id: 91941}}} = Writes.destroy(Repo, ctx.user, 91941)
    assert Repo.query!("SELECT id FROM tags ORDER BY id").rows == [[91942], [91951]]
    assert Repo.query!("SELECT id FROM taggings ORDER BY id").rows == [[919_414], [919_415]]
    assert Repo.query!("SELECT to_jsonb(p)::text FROM places p ORDER BY id").rows == places
    assert Repo.query!("SELECT * FROM visits ORDER BY id").rows == visits
    assert commands() == []
  end

  test "no-op and adopted timestamps match Rails", ctx do
    tag!(ctx.user, 91941, "Owned", %{icon: "", color: ""})
    tag!(ctx.user, 91942, "Demo", %{demo: true})
    before = state()
    assert {:ok, _} = Writes.update(Repo, ctx.user, 91941, %{"name" => "Owned"}, ctx.write_ctx)
    assert {:ok, _} = Writes.update(Repo, ctx.user, 91941, %{}, ctx.write_ctx)
    assert state() == before
    later = Map.put(ctx.write_ctx, :adopt_now, fn -> ~U[2026-10-03 10:00:01.000000Z] end)
    assert {:ok, result} = Writes.update(Repo, ctx.user, 91942, %{"name" => "Demo"}, later)
    assert result.tag.demo == false
    assert result.tag.updated_at == ~N[2026-10-03 10:00:01.000000]
    assert result.tag.created_at == ~N[2026-10-02 10:00:00.000000]

    assert Repo.query!("SELECT updated_at,demo FROM tags WHERE id=91942").rows == [
             [~N[2026-10-03 10:00:01.000000], false]
           ]

    assert {:ok, changed} =
             Writes.update(
               Repo,
               ctx.user,
               91941,
               %{"privacy_radius_meters" => "0.5"},
               ctx.write_ctx
             )

    assert changed.tag.privacy_radius_meters == 0
    assert changed.tag.updated_at == ~N[2026-10-03 10:00:00.000000]
    assert commands() == []
  end
end
