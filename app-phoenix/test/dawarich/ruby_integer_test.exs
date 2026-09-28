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
end
