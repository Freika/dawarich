defmodule Dawarich.RepoTest do
  use ExUnit.Case, async: true

  @corpus "../fixtures/jsonb_floats.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  test "reads tables owned by the Rails schema" do
    %{rows: [[exists]]} =
      Dawarich.Repo.query!(
        "SELECT to_regclass('public.users') IS NOT NULL AND to_regclass('public.points') IS NOT NULL"
      )

    assert exists
  end

  test "sessions run in UTC set by the connection's startup parameter" do
    assert %{rows: [["UTC", "client"]]} =
             Dawarich.Repo.query!(
               "SELECT setting, source FROM pg_settings WHERE name = 'TimeZone'"
             )
  end

  test "jsonb parameters are stored exactly as ActiveRecord with Oj stores the same values" do
    pairs =
      Enum.map(@corpus["floats"], fn [hex, text] -> {%{"v" => float(hex)}, ~s({"v":#{text}})} end) ++
        Enum.flat_map(@corpus["documents"], fn %{"hex" => hex} = row ->
          value = float(hex)

          [
            {%{"v" => value}, row["string_keys"]},
            {[value], row["array"]},
            {%{"a" => %{"b" => [value, %{"c" => value}]}}, row["nested"]}
          ]
        end)

    {terms, texts} = Enum.unzip(pairs)

    %{rows: rows} =
      Dawarich.Repo.query!(
        "SELECT a::text, b::text::jsonb::text FROM unnest($1::jsonb[], $2::text[]) AS t(a, b)",
        [terms, texts]
      )

    mismatches = for [stored, rails] <- rows, stored != rails, do: {stored, rails}

    assert {length(rows), length(mismatches), Enum.take(mismatches, 3)} ==
             {length(pairs), 0, []}
  end

  defp float(hex) do
    <<value::float>> = Base.decode16!(hex, case: :lower)
    value
  end
end
