defmodule Dawarich.Places.WebWriteTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Places.WebWrite
  alias Dawarich.Test.FrameSeeds

  @effects File.read!("test/fixtures/places/remaining/effects.json")
           |> Jason.decode!()
           |> Map.fetch!("effects")
  @now ~U[2026-10-02 10:00:00.000000Z]
  @fields ~w(id user_id name latitude longitude source note name_locked_at demo created_at updated_at)

  defmodule TagFailure do
    defdelegate transaction(fun), to: Dawarich.Repo

    def query!(sql, params, opts \\ []) do
      if String.contains?(sql, "INSERT INTO taggings"), do: raise("tag-save phase failure")
      Dawarich.Repo.query!(sql, params, opts)
    end
  end

  defp value(key, raw) do
    cond do
      is_nil(raw) ->
        nil

      key in ~w(created_at updated_at name_locked_at) ->
        raw |> DateTime.from_iso8601() |> elem(1) |> DateTime.to_naive()

      key in ~w(latitude longitude) ->
        Decimal.normalize(Decimal.new(raw))

      key == "source" ->
        Map.get(%{"manual" => 0, "photon" => 1, "gpx_waypoint" => 2}, raw)

      true ->
        raw
    end
  end

  defp places(id) do
    Repo.query!(
      "SELECT #{Enum.join(@fields, ",")}, ST_X(lonlat::geometry), ST_Y(lonlat::geometry) FROM places WHERE id >= $1 AND id < $1+20 ORDER BY id",
      [id]
    ).rows
    |> Enum.map(fn row ->
      Enum.map(row, fn value ->
        if is_struct(value, Decimal), do: Decimal.normalize(value), else: value
      end)
    end)
  end

  defp expected_places(rows),
    do:
      for(
        row <- rows,
        do:
          Enum.map(@fields, &value(&1, row[&1])) ++
            if(row["lonlat"], do: row["lonlat"], else: [nil, nil])
      )

  defp taggings(id),
    do:
      Repo.query!(
        "SELECT id, tag_id, taggable_type, taggable_id, created_at, updated_at FROM taggings WHERE taggable_type='Place' AND taggable_id >= $1 AND taggable_id < $1+20 ORDER BY id",
        [id]
      ).rows

  defp expected_tags(rows),
    do:
      for(
        row <- rows,
        do:
          Enum.map(
            ~w(id tag_id taggable_type taggable_id created_at updated_at),
            &value(&1, row[&1])
          )
      )

  test "web saves preserve name locks tags adoption and phases" do
    for entry <- @effects,
        entry["request"]["method"] in ~w(post patch),
        not String.starts_with?(entry["name"], "foreign_") do
      user = FrameSeeds.seed_place_remainder!(entry)
      id = hd(entry["before"]["places"])["id"]
      action = if entry["request"]["method"] == "post", do: :create, else: :update
      attrs = entry["request"]["params"]["place"]

      result =
        WebWrite.run(Repo, action, user, if(action == :create, do: nil, else: id), attrs, %{
          now: @now
        })

      unsupported =
        attrs["source"] == "bogus" or
          (action == :update and
             Enum.any?(
               ~w(latitude longitude),
               &(Map.has_key?(attrs, &1) and attrs[&1] in [nil, ""])
             ))

      cond do
        unsupported ->
          assert match?({:replay, _}, result), entry["name"]

        entry["after"]["places"] == entry["before"]["places"] and attrs["name"] != "Before" and
            action == :create ->
          assert match?({:invalid, _}, result), entry["name"]

        attrs["name"] == "" or
            (is_binary(attrs["name"]) and length(String.codepoints(attrs["name"])) > 255) ->
          assert match?({:invalid, _}, result), entry["name"]

        true ->
          assert match?({:ok, _}, result), entry["name"]
      end

      assert places(id) == expected_places(entry["after"]["places"]),
             entry["name"] <>
               inspect({places(id), expected_places(entry["after"]["places"])}, limit: :infinity)

      assert taggings(id) == expected_tags(entry["after"]["taggings"]), entry["name"]
    end

    entry = Enum.find(@effects, &(&1["name"] == "update_demo_html_false"))
    id = hd(entry["before"]["places"])["id"]
    Repo.query!("UPDATE places SET demo=true,name='Before' WHERE id=$1", [id])
    user = Dawarich.Accounts.get(entry["before"]["actor"]["id"])

    assert_raise RuntimeError, "tag-save phase failure", fn ->
      WebWrite.run(
        TagFailure,
        :update,
        user,
        id,
        %{"name" => "Saved before tags", "tag_ids" => [id + 1]},
        %{now: @now}
      )
    end

    assert Repo.query!("SELECT name,demo,name_locked_at,updated_at FROM places WHERE id=$1", [id]).rows ==
             [["Saved before tags", false, DateTime.to_naive(@now), DateTime.to_naive(@now)]]

    entry = Enum.find(@effects, &(&1["name"] == "foreign_update_html_false"))
    user = FrameSeeds.seed_place_remainder!(entry)
    id = hd(entry["before"]["places"])["id"]

    assert {:error, :not_found} =
             WebWrite.run(Repo, :update, user, id, %{"name" => "Forbidden"}, %{now: @now})

    before = places(id)
    Repo.query!("UPDATE places SET lonlat=NULL WHERE id=$1", [id])
    foreign = hd(entry["before"]["places"])["user_id"]

    assert {:replay, _} =
             WebWrite.run(
               Repo,
               :update,
               Dawarich.Accounts.get(foreign),
               id,
               %{"name" => "Legacy"},
               %{now: @now}
             )

    assert Enum.take(hd(places(id)), length(@fields)) == Enum.take(hd(before), length(@fields))
    assert commands() == []
  end
end
