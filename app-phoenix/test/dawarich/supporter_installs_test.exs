defmodule Dawarich.SupporterInstallsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Accounts
  alias Dawarich.Settings.Api
  alias Dawarich.Test.RailsUser

  setup do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "supporter-installs-#{id}@example.test"})
    %{id: id}
  end

  defp report(id, active, install) do
    ctx = %{now: DateTime.utc_now(), self_hosted?: true}

    settings =
      if install == :none,
        do: %{"app_store_supporter" => active},
        else: %{"app_store_supporter" => active, "app_store_supporter_install" => install}

    assert {:ok, 200, _} = Api.update(Repo, Accounts.get(id), %{"settings" => settings}, ctx)
    Api.read(Repo, id)
  end

  test "keeps the flag while another install is still subscribed", %{id: id} do
    report(id, true, "install-a")
    report(id, true, "install-b")
    assert report(id, false, "install-a")["app_store_supporter"] == true
  end

  test "clears the flag once every reporting install has lapsed", %{id: id} do
    report(id, true, "install-a")
    report(id, true, "install-b")
    report(id, false, "install-a")
    assert report(id, false, "install-b")["app_store_supporter"] == false
  end

  test "counts an install once however often it reports", %{id: id} do
    report(id, true, "install-a")
    settings = report(id, true, "install-a")
    assert settings["app_store_supporter_installs"] == ["install-a"]
    assert report(id, false, "install-a")["app_store_supporter"] == false
  end

  test "the install id is stripped and never stored as its own setting", %{id: id} do
    settings = report(id, "true", "  install-a \n")
    assert settings["app_store_supporter_installs"] == ["install-a"]
    assert settings["app_store_supporter"] == true
    refute Map.has_key?(settings, "app_store_supporter_install")
  end

  test "a blank, overlong or non-string install id keeps the plain flag", %{id: id} do
    for install <- ["   ", String.duplicate("x", 129), 42] do
      settings = report(id, "0", install)
      assert settings["app_store_supporter"] == "0"
      refute Map.has_key?(settings, "app_store_supporter_installs")
      refute Map.has_key?(settings, "app_store_supporter_install")
    end

    assert report(id, true, String.duplicate("x", 128))["app_store_supporter_installs"] == [
             String.duplicate("x", 128)
           ]
  end
end
