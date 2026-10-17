defmodule Dawarich.Sync1160AddressTest do
  use ExUnit.Case, async: true
  alias Dawarich.Address

  test "place address normalizes Photon feature collections and flat provider data" do
    photon = %{
      "properties" => %{
        "street" => "Main",
        "housenumber" => "12",
        "postcode" => "04275",
        "city" => "Leipzig",
        "country" => "Germany"
      }
    }

    flat = %{
      "address" => %{
        "road" => "Main",
        "house_number" => "12",
        "postcode" => "04275",
        "town" => "Leipzig",
        "country" => "Germany"
      }
    }

    assert Address.manual(%{
             "street" => 42,
             "city" => 0,
             "country" => true,
             "house_number" => false,
             "postcode" => []
           }) ==
             %{"properties" => %{"street" => 42, "city" => 0, "country" => true}}

    for data <- [photon, flat, %{"features" => [photon]}] do
      assert Address.place(data) == "Main 12, 04275 Leipzig"
      assert Address.point(data) == "Main, Leipzig, Germany"
    end

    for data <- [nil, [], %{}, %{"properties" => %{"street" => " ", "city" => ""}}] do
      assert Address.place(data) == nil
      assert Address.point(data) == nil
    end
  end
end
