defmodule Dawarich.TagPagesTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Repo, TagPages}
  alias Dawarich.Test.FrameSeeds

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    %{owner: FrameSeeds.user!(8381), foreign: FrameSeeds.user!(8382)}
  end

  defp tag!(user, id, name, attrs \\ %{}) do
    Repo.insert_all("tags", [
      Map.merge(
        %{
          id: id,
          user_id: user.id,
          name: name,
          created_at: ~N[2026-03-01 10:00:00],
          updated_at: ~N[2026-03-01 10:00:00]
        },
        attrs
      )
    ])
  end

  test "ordered tags exclude other users and count only Place taggings", %{
    owner: owner,
    foreign: foreign
  } do
    tag!(owner, 83811, "Work")
    tag!(owner, 83812, "Home & <café>")
    tag!(foreign, 83813, "Foreign")
    FrameSeeds.place!(owner.id, 838_101, "Synthetic home")
    FrameSeeds.place!(owner.id, 838_102, "Synthetic work")

    FrameSeeds.visit!(owner.id, 838_101, %{
      started_at: ~N[2026-03-01 10:00:00],
      ended_at: ~N[2026-03-01 10:30:00]
    })

    for {id, tag_id, row_id, type} <- [
          {838_111, 83812, 838_101, "Place"},
          {838_112, 83811, 838_102, "Place"},
          {838_113, 83812, 838_101, "Visit"}
        ] do
      Repo.insert_all("taggings", [
        %{
          id: id,
          tag_id: tag_id,
          taggable_id: row_id,
          taggable_type: type,
          created_at: ~N[2026-03-01 10:00:00],
          updated_at: ~N[2026-03-01 10:00:00]
        }
      ])
    end

    assert [%{id: 83812, places_count: 1}, %{id: 83811, places_count: 1}] = TagPages.index(owner)
    assert [] == TagPages.index(%{owner | id: 8383})
  end

  test "edit only loads an owned tag", %{owner: owner, foreign: foreign} do
    tag!(owner, 83821, "Owned")
    tag!(foreign, 83822, "Foreign")
    assert {:ok, %{id: 83821, name: "Owned"}} = TagPages.edit(owner, 83821)
    assert :not_found = TagPages.edit(owner, 83822)
    assert :not_found = TagPages.edit(owner, 999_999)
  end

  test "edit preserves blank fields demo and privacy attributes", %{owner: owner} do
    tag!(owner, 83831, "Private", %{icon: "", color: "", demo: true, privacy_radius_meters: 750})
    assert {:ok, row} = TagPages.edit(owner, 83831)
    assert %{icon: "", color: "", demo: true, privacy_radius_meters: 750} = row
    tag!(owner, 83832, "Public")

    assert {:ok, %{icon: nil, color: nil, demo: false, privacy_radius_meters: nil}} =
             TagPages.edit(owner, 83832)
  end
end
