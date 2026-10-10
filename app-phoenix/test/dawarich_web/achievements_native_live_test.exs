defmodule DawarichWeb.AchievementsNativeLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{NativeAdminUI, NativeAchievementsUI}
  @endpoint DawarichWeb.Endpoint

  setup do
    %{target: user} = NativeAdminUI.setup!()
    %{user: user}
  end

  test "achievement filter search page history preserves selection and clears revoked cards", %{
    user: user
  } do
    {:ok, view, _} =
      live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

    assert has_element?(view, "#achievement-filter")
    render_click(view, "select_card", %{"key" => "country_fr"})
    assert has_element?(view, "#achievement-dialog [data-selected-key='country_fr']")
    render_patch(view, "/achievements/continent_europe?status=locked&q=France")
    assert has_element?(view, "#achievement-dialog [data-selected-key='country_fr']")
    assert has_element?(view, "input[name=q][value=France]")
    render_patch(view, "/achievements/continent_europe?page=99")
    refute has_element?(view, "#achievement-dialog [data-selected-key]")
    render_patch(view, "/achievements/continent_europe")
    assert length(:sys.get_state(view.pid).socket.assigns.data.view.children) <= 12
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [user.id], log: false)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             render_patch(view, "/achievements/continent_europe?q=France")
  end

  test "card dialog Escape and close return focus to the chosen card", %{user: user} do
    {:ok, view, html} =
      live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

    refute html =~ "RailsStimulus"
    refute html =~ "data-controller="
    render_click(view, "select_card", %{"key" => "country_fr"})

    assert has_element?(
             view,
             "#achievement-dialog[phx-window-keydown*='close_card'][phx-key='Escape']"
           )

    assert has_element?(view, "#close-achievement-card[phx-click*='pop_focus']")
    assert has_element?(view, "#achievement-country_fr[phx-click*='push_focus']")
    render_click(view, "close_card", %{})
    refute has_element?(view, "#achievement-dialog [data-selected-key]")
  end

  test "connected render and reconnect do not celebrate twice", %{user: user} do
    earned =
      Map.new(
        Dawarich.Achievements.Registry.find("country_de").region_codes,
        &{&1, "2026-07-19T10:00:00Z"}
      )

    Repo.query!(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
      [user.id, %{"earned" => earned}], log: false)

    conn = NativeAchievementsUI.conn(user, "/achievements/country_de")

    assert [[nil]] =
             Repo.query!(
               "SELECT state->'celebrated' FROM achievement_progresses WHERE user_id=$1",
               [user.id], log: false).rows

    {:ok, first, _} = live(conn)
    assert has_element?(first, "[data-celebrate=true]")
    {:ok, second, _} = live(NativeAchievementsUI.conn(user, "/achievements/country_de"))
    refute has_element?(second, "[data-celebrate=true]")

    refute :erlang.term_to_binary(:sys.get_state(first.pid).socket.assigns) =~
             Accounts.get(user.id).encrypted_password
  end

  test "native achievement sharing reflects a second tab revocation and stale identity refuses",
       %{user: user} do
    {:ok, view, _} = live(NativeAchievementsUI.conn(user, "/achievements/country_de"))
    render_click(view, "select_card", %{"key" => "country_de"})
    render_click(view, "share_card", %{"enabled" => "true"})
    assert has_element?(view, "#achievement-share-output[value*='/shared/achievements/']")

    Repo.query!(
      "UPDATE achievement_progresses SET sharing_enabled=false WHERE user_id=$1 AND achievement_key='country_de'",
      [user.id], log: false)

    render_patch(view, "/achievements/country_de")
    refute has_element?(view, "#achievement-share-output")

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-00000000000000000000000' WHERE id=$1",
      [user.id], log: false)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             render_click(view, "share_card", %{"enabled" => "true"})
  end
end
