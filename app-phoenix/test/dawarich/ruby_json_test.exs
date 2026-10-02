defmodule Dawarich.RubyJsonTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree
  alias Dawarich.RubyJson

  @corpus "../fixtures/jsonb_floats.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()

  test "the corpus comes from the Ruby, Oj and jsonb serializer the Rails tree pins" do
    assert String.trim(RailsTree.read(".ruby-version")) == @corpus["ruby"]
    assert @corpus["oj"] == oj_version()
    assert @corpus["serializer"] == "ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb"
    assert length(@corpus["floats"]) in 2900..3300
  end

  test "encodes every corpus float as ActiveRecord's jsonb serializer did" do
    for [hex, text] <- @corpus["floats"] do
      assert encode(%{"v" => float(hex)}) == ~s({"v":#{text}}), hex
    end
  end

  test "encodes floats in string and atom keyed maps, lists and nested documents as Rails did" do
    for %{"hex" => hex} = row <- @corpus["documents"] do
      value = float(hex)
      assert encode(%{"v" => value}) == row["string_keys"], hex
      assert encode(%{v: value}) == row["symbol_keys"], hex
      assert encode([value]) == row["array"], hex
      assert encode(%{"a" => %{"b" => [value, %{"c" => value}]}}) == row["nested"], hex
    end
  end

  test "encodes floats inside an ordered object, keeping its key order" do
    object = Jason.OrderedObject.new([{"b", 0.1 + 0.2}, {"a", [1000.0, 1.0e-5]}])

    assert encode(object) == ~s({"b":0.3,"a":[1000.0,1e-05]})
  end

  test "leaves structs to Jason, as in Oban's error rows and decimals" do
    error = %{"at" => ~U[2026-10-02 12:00:00.123456Z], "attempt" => 1, "error" => "boom"}
    decimal = %{"amount" => Decimal.new("0.30000000000000004")}

    for term <- [error, decimal, [error, decimal]] do
      assert encode(term) == IO.iodata_to_binary(Jason.encode_to_iodata!(term))
    end
  end

  test "decodes as Jason does" do
    assert RubyJson.decode!(~s({"v":1000.0,"w":[1,0.3]})) === %{"v" => 1000.0, "w" => [1, 0.3]}
  end

  defp encode(term), do: term |> RubyJson.encode_to_iodata!() |> IO.iodata_to_binary()

  defp float(hex) do
    <<value::float>> = Base.decode16!(hex, case: :lower)
    value
  end

  defp oj_version do
    [_, version] = Regex.run(~r/^    oj \((\S+)\)$/m, RailsTree.read("Gemfile.lock"))
    version
  end
end
