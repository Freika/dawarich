defmodule Dawarich.RubyDecimalTest do
  use ExUnit.Case, async: true

  alias Dawarich.RubyDecimal

  test "fixed/2 is Ruby's %.Nf" do
    assert RubyDecimal.fixed(1.000005, 5) == "1.00000"
    assert RubyDecimal.fixed(0.015625, 5) == "0.01562"
    assert RubyDecimal.fixed(-0.000001, 5) == "-0.00000"
    assert RubyDecimal.fixed(116.321965, 5) == "116.32196"
  end

  test "column/3 is ActiveModel's decimal cast" do
    assert RubyDecimal.column(51.33971249996, 10, 6) == "51.339712"
    assert RubyDecimal.column(12345.678925, 10, 6) == "12345.678920"
    assert RubyDecimal.column(0.25, 1, 1) == "0.3"
    assert RubyDecimal.column(0.15, 1, 1) == "0.2"
  end
end
