defmodule Dawarich.Tags.ValidationTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Test.RailsUser
  alias Dawarich.Tags.Validation

  setup do
    actor = RailsUser.insert!(%{id: 9184, email: "a6s4-validation@example.invalid"})
    foreign = RailsUser.insert!(%{id: 9185, email: "a6s4-foreign@example.invalid"})
    stamp = ~N[2026-10-02 10:00:00]

    tag = %{
      id: 91841,
      user_id: actor.id,
      name: "Existing",
      icon: "☕",
      color: "#abc",
      demo: true,
      privacy_radius_meters: 100,
      created_at: stamp,
      updated_at: stamp
    }

    Repo.insert_all("tags", [tag, %{tag | id: 91851, user_id: foreign.id, name: "Foreign"}])
    %{user: actor, tag: tag}
  end

  defp oracle(name) do
    Path.expand("../../fixtures/map_writes/tags/#{name}.json", __DIR__)
    |> File.read!()
    |> Jason.decode!()
  end

  defp compare(ctx, name) do
    data = oracle(name)
    result = Validation.validate(Repo, ctx.user, data["request"]["params"]["tag"], %{}, "en")
    assert is_map(result)
    assert result.valid == data["validation"]["valid"]
    assert result.raw_radius == data["validation"]["raw_radius"]
    assert result.tag.privacy_radius_meters == data["validation"]["cast_radius"]
    assert result.errors == data["validation"]["errors"]

    assert Map.take(result.tag, ~w(name icon color privacy_radius_meters demo)a)
           |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end) ==
             data["validation"]["attributes"]

    result
  end

  test "presence owner-uniqueness Unicode icon color radius errors retain order", ctx do
    for name <-
          ~w(create_full create_omitted create_foreign_name blank_name unicode_blank_name duplicate_name
                   icon_ten icon_eleven icon_ascii icon_symbol icon_blank color_short color_bad color_blank multi_error) do
      compare(ctx, name)
    end

    assert Repo.query!("SELECT count(*) FROM tags").rows == [[2]]
  end

  test "empty radius casts nil and skips numericality", ctx do
    result = compare(ctx, "radius_blank")
    assert result.valid
    assert result.tag.privacy_radius_meters == nil
    assert result.errors == []
  end

  test "raw radius numericality differs from integer storage with ordered errors", ctx do
    for name <-
          ~w(radius_one radius_limit radius_zero radius_negative radius_over radius_nonnumeric
                   radius_decimal_small radius_decimal_over radius_prefix radius_exponent radius_space radius_plus radius_hex) do
      compare(ctx, name)
    end

    assert Validation.validate(
             Repo,
             ctx.user,
             %{"name" => "Unsupported", "privacy_radius_meters" => "1_000"},
             %{},
             "en"
           ) == :rails

    for raw <- [".5", "1e9999", <<0, ?1>>, <<?1, 0>>] do
      assert Validation.validate(
               Repo,
               ctx.user,
               %{"name" => "Unsupported", "privacy_radius_meters" => raw},
               %{},
               "en"
             ) == :rails
    end
  end

  test "partial update keeps absent fields and duplicate lookup excludes self", ctx do
    result = Validation.validate(Repo, ctx.user, %{"name" => "Existing"}, ctx.tag, "en")
    assert result.valid
    assert result.errors == []
    assert result.tag.icon == "☕"
    assert result.tag.color == "#abc"
    assert result.tag.privacy_radius_meters == 100
    assert result.raw_radius == 100
    assert result.tag.demo
    taken = Validation.validate(Repo, ctx.user, %{"name" => "Existing"}, %{}, "en")
    assert Enum.map(taken.errors, & &1["type"]) == ["taken"]
    assert Repo.query!("SELECT count(*) FROM tags").rows == [[2]]
  end

  test "Unicode radius whitespace follows Rails numeric stripping and blank handling", ctx do
    compare(ctx, "radius_unicode_space")
    compare(ctx, "radius_unicode_blank")
  end

  test "radius comparison rounds noninteger strings to Rails fifteen significant digits", ctx do
    compare(ctx, "radius_precision_limit")
    compare(ctx, "radius_precision_exponent")
  end
end
