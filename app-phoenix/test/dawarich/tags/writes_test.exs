defmodule Dawarich.Tags.WritesTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Tags.Writes
  alias Dawarich.Test.RailsUser

  setup do
    user = RailsUser.insert!(%{id: 9194, email: "a6s4-writes@example.invalid"})
    foreign = RailsUser.insert!(%{id: 9195, email: "a6s4-writes-foreign@example.invalid"})
    ctx = %{now: ~U[2026-10-03 10:00:00Z], locale: "en"}
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
          created_at: ~N[2026-10-02 10:00:00],
          updated_at: ~N[2026-10-02 10:00:00]
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
    assert result.tag.created_at == ~N[2026-10-03 10:00:00]
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

    assert :rails =
             Writes.create(
               Repo,
               ctx.user,
               %{"name" => "Render race"},
               Map.put(ctx.write_ctx, :render, fn _ -> :rails end)
             )

    assert state() == before
    assert commands() == []
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
end
