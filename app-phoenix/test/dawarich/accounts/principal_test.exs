defmodule Dawarich.Accounts.PrincipalTest do
  use ExUnit.Case, async: true

  alias Dawarich.Accounts.{Principal, User}

  test "opaque principal settings retain an unsupported marker without private values or crashes" do
    for settings <- [[], 42, "synthetic-private-settings", false] do
      principal = Principal.project(%User{id: 1, settings: settings})
      assert principal.settings["maps"] == %{"distance_unit" => "km"}
      assert {:ok, safe} = Dawarich.Accounts.settings_for(principal)
      assert safe == principal.settings

      assert Dawarich.Accounts.settings_for(%{principal | settings: :unsupported}) ==
               {:error, :unsupported}

      refute inspect(principal) =~ "synthetic-private-settings"
    end
  end
end
