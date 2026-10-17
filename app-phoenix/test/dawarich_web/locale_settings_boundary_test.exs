defmodule DawarichWeb.LocaleSettingsBoundaryTest do
  use Dawarich.DataCase, async: true
  import Plug.Conn
  require Phoenix.ConnTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.Locale
  @endpoint DawarichWeb.Endpoint

  setup do
    user =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "locale-boundary@example.invalid"
      })

    %{user: user}
  end

  test "locale selection outside Places preserves opaque settings and remembers only the session",
       %{user: user} do
    for value <- [[], 42, "opaque", false] do
      store(user, value)
      before = snapshot(user)
      actor = Accounts.get(user.id)
      conn = locale_conn(actor)
      assert conn.assigns.locale == "de"
      assert conn.assigns.rails_session["locale"] == "de"
      assert conn.assigns.current_user.settings == value
      assert snapshot(user) == before
      response = Phoenix.ConnTest.get(RailsUser.signed_in(user.id), "/settings/general?locale=de")
      assert response.status == 200
      assert response.assigns.locale == "de"
      assert snapshot(user) == before
    end
  end

  test "locale persistence refuses a persisted shape changed after the actor read", %{user: user} do
    for value <- [[], 42, "opaque", false] do
      store(user, %{"timezone" => "UTC", "kept" => true})
      actor = Accounts.get(user.id)
      store(user, value)
      before = snapshot(user)
      conn = locale_conn(actor)
      assert conn.assigns.locale == "de"
      assert snapshot(user) == before
      assert Accounts.persist_locale(user.id, "fr") == {:error, :unsupported}
      assert snapshot(user) == before
    end

    for value <- [nil, %{"kept" => true}] do
      store(user, value)
      locale_conn(Accounts.get(user.id))
      [[settings, _]] = snapshot(user)
      assert settings == Map.put(value || %{}, "locale", "de")
    end
  end

  defp locale_conn(actor) do
    Plug.Test.conn(:get, "/settings/general?locale=de")
    |> fetch_query_params()
    |> assign(:current_user, actor)
    |> assign(:rails_session, %{})
    |> Locale.call([])
  end

  defp store(user, value),
    do: Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, value], log: false)

  defp snapshot(user),
    do:
      Repo.query!("SELECT settings,updated_at FROM users WHERE id=$1", [user.id], log: false).rows
end
