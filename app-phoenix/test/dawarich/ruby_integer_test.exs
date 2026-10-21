defmodule Dawarich.RubyIntegerTest do
  use ExUnit.Case, async: true

  alias Dawarich.RubyInteger

  test "matches Ruby's to_i" do
    assert RubyInteger.to_i("  7x") == 7
    assert RubyInteger.to_i("x") == 0
    assert RubyInteger.to_i(12.9) == 12
    assert RubyInteger.to_i(nil) == 0
    assert RubyInteger.to_i(-3) == -3
  end

  test "matches Ruby 3.4's String#to_i on underscores, signs and whitespace" do
    for {string, ruby} <- [
          {"1_000", 1000},
          {"1__000", 1},
          {"_1", 0},
          {"1_", 1},
          {"-1_2", -12},
          {"+_1", 0},
          {" _1", 0},
          {"+5", 5},
          {"- 5", 0},
          {" 5", 0},
          {" 5", 0},
          {"\u00857", 0},
          {"\t\n\v\f\r 7x", 7},
          {"0x1A", 0},
          {"007", 7},
          {"1e5", 1},
          {"12.9", 12},
          {"", 0},
          {"-0", 0},
          {"1_000_", 1000},
          {"٣", 0},
          {"12_3_4", 1234},
          {"+-1", 0},
          {"  -42abc", -42}
        ] do
      assert {string, RubyInteger.to_i(string)} == {string, ruby}
    end
  end
end
