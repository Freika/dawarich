defmodule Dawarich.TagsTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Accounts.Scope
  alias Dawarich.{Repo, Tags}
  alias Dawarich.Test.FrameSeeds

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.user!(8394)
    other = FrameSeeds.user!(8395)
    %{scope: Scope.for_user(owner, "en"), other: Scope.for_user(other, "en")}
  end

  defp tag_rows(user_id),
    do:
      Repo.query!(
        "SELECT name, icon, color, privacy_radius_meters, demo FROM tags WHERE user_id=$1 ORDER BY name",
        [user_id]
      ).rows

  defp params(extra \\ %{}),
    do:
      Map.merge(
        %{
          "name" => "Home",
          "icon" => "🏠",
          "color" => "#ef4444",
          "privacy_radius_meters" => "750"
        },
        extra
      )

  defp error(changeset, field),
    do: changeset.errors |> Keyword.get_values(field) |> Enum.map(&elem(&1, 0))

  test "create_tag stores a tag owned by the scope user", %{scope: scope} do
    assert {:ok, tag} = Tags.create_tag(scope, params())
    assert tag.name == "Home"
    assert tag_rows(scope.user.id) == [["Home", "🏠", "#ef4444", 750, false]]
  end

  test "LiveView bookkeeping and form-only keys do not break validation or saving", %{
    scope: scope
  } do
    form =
      params(%{
        "_unused_name" => "",
        "_target" => ["tag", "name"],
        "custom_color" => "#000000",
        "privacy_enabled" => "true"
      })

    assert %Ecto.Changeset{valid?: true} = Tags.change_tag(scope, Tags.new_tag(), form)
    assert {:ok, _} = Tags.create_tag(scope, form)
  end

  test "a duplicate name for the same user is taken; other users may reuse it", %{
    scope: scope,
    other: other
  } do
    {:ok, _} = Tags.create_tag(scope, params())

    assert {:error, changeset} = Tags.create_tag(scope, params())
    assert error(changeset, :name) == ["Name has already been taken"]
    assert {:ok, _} = Tags.create_tag(other, params())
  end

  test "a second create of the same name from another process keeps one row and reports taken", %{
    scope: scope
  } do
    parent = self()

    results =
      for _ <- 1..2 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Tags.create_tag(scope, params(%{"name" => "Race"}))
        end)
      end
      |> Enum.map(&Task.await/1)

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1
    assert [{:error, changeset}] = Enum.filter(results, &match?({:error, _}, &1))
    assert error(changeset, :name) == ["Name has already been taken"]

    assert Repo.query!("SELECT count(*) FROM tags WHERE user_id=$1 AND name='Race'", [
             scope.user.id
           ]).rows == [[1]]
  end

  test "invalid radii carry the Rails messages", %{scope: scope} do
    for {radius, message} <- [
          {"-5", "Privacy radius meters must be greater than 0"},
          {"abc", "Privacy radius meters is not a number"},
          {"5001", "Privacy radius meters must be less than or equal to 5000"}
        ] do
      assert {:error, changeset} =
               Tags.create_tag(scope, params(%{"privacy_radius_meters" => radius}))

      assert error(changeset, :privacy_radius_meters) == [message], radius
    end

    assert tag_rows(scope.user.id) == []
  end

  test "a radius Rails would not parse is reported as not a number instead of handing back", %{
    scope: scope
  } do
    for radius <- ["1_000", "99999999999"] do
      assert {:error, changeset} =
               Tags.create_tag(scope, params(%{"privacy_radius_meters" => radius}))

      assert error(changeset, :privacy_radius_meters) == ["Privacy radius meters is not a number"],
             radius
    end
  end

  test "privacy off clears the radius and privacy on without a value stores 1000", %{scope: scope} do
    {:ok, tag} = Tags.create_tag(scope, params())

    {:ok, _} = Tags.update_tag(scope, tag, params(%{"privacy_enabled" => "false"}))
    assert [[_, _, _, nil, _]] = tag_rows(scope.user.id)

    {:ok, tag} = Tags.get_tag(scope, tag.id)

    {:ok, _} =
      Tags.update_tag(
        scope,
        tag,
        params(%{"privacy_enabled" => "true", "privacy_radius_meters" => ""})
      )

    assert [[_, _, _, 1000, _]] = tag_rows(scope.user.id)
  end

  test "foreign, malformed and oversized ids are not found and change nothing", %{
    scope: scope,
    other: other
  } do
    {:ok, tag} = Tags.create_tag(other, params())

    for id <- [tag.id, to_string(tag.id), "abc", "0", String.duplicate("9", 30)] do
      assert Tags.get_tag(scope, id) == {:error, :not_found}
      assert Tags.delete_tag(scope, id) == {:error, :not_found}
    end

    assert Tags.update_tag(scope, tag, params(%{"name" => "Hijack"})) == {:error, :not_found}
    assert tag_rows(other.user.id) == [["Home", "🏠", "#ef4444", 750, false]]
  end

  test "editing a demo tag adopts it", %{scope: scope} do
    {:ok, tag} = Tags.create_tag(scope, params())
    Repo.query!("UPDATE tags SET demo=true WHERE id=$1", [tag.id])
    {:ok, tag} = Tags.get_tag(scope, tag.id)

    assert {:ok, _} = Tags.update_tag(scope, tag, params(%{"name" => "Adopted"}))
    assert [["Adopted", _, _, _, false]] = tag_rows(scope.user.id)
  end

  test "delete_tag removes the tag and its taggings", %{scope: scope} do
    {:ok, tag} = Tags.create_tag(scope, params())
    FrameSeeds.place!(scope.user.id, 839_501, "Cafe")
    now = NaiveDateTime.utc_now()

    Repo.insert_all("taggings", [
      %{
        tag_id: tag.id,
        taggable_id: 839_501,
        taggable_type: "Place",
        created_at: now,
        updated_at: now
      }
    ])

    assert {:ok, _} = Tags.delete_tag(scope, tag.id)
    assert tag_rows(scope.user.id) == []
    assert Repo.query!("SELECT count(*) FROM taggings WHERE tag_id=$1", [tag.id]).rows == [[0]]
  end

  test "list_tags returns own tags by name with place counts", %{scope: scope, other: other} do
    {:ok, b} = Tags.create_tag(scope, params(%{"name" => "B"}))
    {:ok, _} = Tags.create_tag(scope, params(%{"name" => "A"}))
    {:ok, _} = Tags.create_tag(other, params(%{"name" => "Theirs"}))
    FrameSeeds.place!(scope.user.id, 839_502, "Park")
    now = NaiveDateTime.utc_now()

    Repo.insert_all("taggings", [
      %{
        tag_id: b.id,
        taggable_id: 839_502,
        taggable_type: "Place",
        created_at: now,
        updated_at: now
      }
    ])

    assert Enum.map(Tags.list_tags(scope), &{&1.name, &1.places_count}) == [{"A", 0}, {"B", 1}]
  end
end
