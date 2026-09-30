defmodule Dawarich.Geocoding.ProvidersTest do
  use ExUnit.Case, async: true

  alias Dawarich.Geocoding.Providers

  test "bare_host follows Ruby's split" do
    assert Providers.bare_host(nil) == nil
    assert Providers.bare_host("") == nil
    assert Providers.bare_host("/x") == nil
    assert Providers.bare_host(":8080") == ""
    assert Providers.bare_host("h:443/p") == "h"
  end
end
