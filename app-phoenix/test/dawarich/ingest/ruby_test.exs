defmodule Dawarich.Ingest.RubyTest do
  use ExUnit.Case, async: true

  alias Dawarich.Ingest.{Ruby, Unsupported}

  @units "test/fixtures/ingest/units.json" |> File.read!() |> Jason.decode!()

  test "String#to_i and String#to_d match Ruby on the oracle's strings" do
    for %{"input" => input, "to_i" => to_i, "to_d" => to_d} <- @units["strings"] do
      assert Ruby.to_i(input) == to_i, inspect(input)
      assert Decimal.equal?(Ruby.to_d(input), Decimal.new(to_d)), inspect(input)
    end
  end

  test "to_s, to_f and to_i follow Ruby for scalars and hand containers to Rails" do
    assert Ruby.to_s(nil) == ""
    assert Ruby.to_s(1.0e-5) == "1.0e-05"
    assert Ruby.to_s(true) == "true"
    assert Ruby.to_f(nil) == 0.0
    assert Ruby.to_f("0.5abc") == 0.5
    assert Ruby.to_i(12.9) == 12
    assert_raise Unsupported, fn -> Ruby.to_s([1]) end
    assert_raise Unsupported, fn -> Ruby.to_f(true) end
    assert_raise Unsupported, fn -> Ruby.to_f("1e400") end
    assert_raise Unsupported, fn -> Ruby.to_i(%{}) end
  end

  test "at/2 indexes arrays only; dig/2 walks hashes and stops at nil" do
    assert Ruby.at([1, 2], 1) == 2
    assert Ruby.at([1], 1) == nil
    assert_raise Unsupported, fn -> Ruby.at("13,52", 0) end
    assert Ruby.dig(%{"a" => %{"b" => 1}}, ["a", "b"]) == 1
    assert Ruby.dig(%{}, ["a", "b"]) == nil
    assert_raise Unsupported, fn -> Ruby.dig(%{"a" => "x"}, ["a", "b"]) end
  end

  test "truthy? is Ruby truthiness" do
    assert Enum.map([nil, false, 0, "", []], &Ruby.truthy?/1) == [false, false, true, true, true]
  end
end
