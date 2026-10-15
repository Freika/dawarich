defmodule Dawarich.Sync1160SettingsTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, UserSettings}
  alias Dawarich.Settings.{Api, General, Misc}
  alias Dawarich.Families.Sharing
  alias Dawarich.Test.RailsUser

  setup do
    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "sync-settings@example.test"
      })

    %{user: user}
  end

  test "opaque settings read defaults and refuse partial writes without replacing data", %{
    user: user
  } do
    for raw <- [nil, [], ["opaque"], "opaque", 12, true] do
      Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, raw], log: false)
      assert UserSettings.get(Accounts.get(user.id))["maps"]["distance_unit"] == "km"
      refute Sharing.enabled?(raw, DateTime.utc_now())
      assert Sharing.config(raw) == nil
      assert Dawarich.FamilyPageAccess.validate_settings!(raw) == %{}

      if raw != nil do
        assert {:error, _} = General.save(Repo, user.id, %{"news_emails_enabled" => false})

        assert Repo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows ==
                 [[raw]]
      end
    end
  end

  test "theme rejects unknown blank missing and structured values without writes", %{user: user} do
    for value <- ["purple", "", nil, [], %{}] do
      assert Misc.theme(user.id, value) == {:error, :invalid_theme}

      assert Repo.query!("SELECT theme FROM users WHERE id=$1", [user.id], log: false).rows == [
               ["dark"]
             ]
    end

    for theme <- ~w(light dark) do
      assert Misc.theme(user.id, theme) == :ok

      assert Repo.query!("SELECT theme FROM users WHERE id=$1", [user.id], log: false).rows == [
               [theme]
             ]
    end

    for query <- ["theme=purple", "theme=", "", "theme[]=dark"] do
      conn =
        Plug.Test.conn(:get, "/settings/theme?" <> query)
        |> Plug.Test.put_req_cookie(
          "_dawarich_session",
          RailsUser.cookie(RailsUser.session(user.id))
        )
        |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))

      assert conn.status == 422

      assert Repo.query!("SELECT theme FROM users WHERE id=$1", [user.id], log: false).rows == [
               ["dark"]
             ]
    end
  end

  test "settings API stores the App Store flag without extending the Rails response shape", %{
    user: user
  } do
    refute Map.has_key?(Api.config(%{}, false), "app_store_supporter")
    refute "app_store_supporter" in Api.fields()
    ctx = %{now: DateTime.utc_now(), self_hosted?: true}
    actor = Accounts.get(user.id)

    for flag <- [true, false, "true", "0", "off", 0] do
      assert {:ok, 200, _} =
               Api.update(Repo, actor, %{"settings" => %{"app_store_supporter" => flag}}, ctx)

      assert Api.read(Repo, user.id)["app_store_supporter"] == flag
      refute Map.has_key?(Api.config(Api.read(Repo, user.id), false), "app_store_supporter")
    end
  end
end
