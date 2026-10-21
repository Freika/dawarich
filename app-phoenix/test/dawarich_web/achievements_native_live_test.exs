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

  @tag share_output_label: true
  test "achievement share output keeps a localized name before sharing and in both panels" do
    for locale <- ["en", "de"], panel <- [nil, "link", "embed"], shared <- [false, true] do
      html =
        render_component(&DawarichWeb.NativeAchievementDialog.dialog/1,
          locale: locale,
          selected: nil,
          panel: panel,
          share_url: if(shared, do: "/shared/achievements/synthetic"),
          base_url: "https://example.invalid"
        )

      names =
        html
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#achievement-share-output")
        |> LazyHTML.attribute("aria-label")

      key = if panel == "embed", do: "embed_code", else: "public_link"
      assert names == [DawarichWeb.Translate.t(locale, "achievements.modal." <> key, %{})]
    end
  end

  @tag collection_title: true
  test "collection title follows detail and summary navigation", %{user: user} do
    {:ok, view, _} = live(NativeAchievementsUI.conn(user, "/achievements"))
    render_patch(view, "/achievements/country_de")
    assert :sys.get_state(view.pid).socket.assigns.page_title == "Germany Explorer"
    render_patch(view, "/achievements")
    assert has_element?(view, "h1", "Achievements")
    assert :sys.get_state(view.pid).socket.assigns.page_title == "Achievements"
  end

  for field <- ~w(q status) do
    @tag malformed_native_event: true
    test "achievement rejects map #{field} filters in place without losing selection or writing",
         %{user: user} do
      Process.flag(:trap_exit, true)

      {:ok, view, _} =
        live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

      render_click(view, "select_card", %{"key" => "country_fr"})
      before = :sys.get_state(view.pid).socket
      fields = [:data, :selected, :share_url]

      {html, queries} =
        NativeAdminUI.queries(fn ->
          render_hook(view, "filter", %{unquote(field) => %{"nested" => "invalid"}})
        end)

      assert is_binary(html)
      assert Process.alive?(view.pid)
      after_event = :sys.get_state(view.pid).socket
      assert Map.take(after_event.assigns, fields) == Map.take(before.assigns, fields)
      assert after_event.assigns.flash["alert"]
      assert queries != []
      refute Enum.any?(queries, &String.match?(&1, ~r/\A\s*(INSERT|UPDATE|DELETE)\b/i))
      render_submit(view, "filter", %{"q" => "Germany", "status" => "locked"})
      assert :sys.get_state(view.pid).socket.assigns.data.query["q"] == "Germany"
    end
  end

  test "achievement filter search page history preserves selection and clears revoked cards", %{
    user: user
  } do
    {:ok, view, _} =
      live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

    assert has_element?(view, "#native-achievement-filter")
    render_click(view, "select_card", %{"key" => "country_fr"})
    assert has_element?(view, "#native-achievement-dialog [data-selected-key='country_fr']")
    render_patch(view, "/achievements/continent_europe?status=locked&q=France")
    assert has_element?(view, "#native-achievement-dialog [data-selected-key='country_fr']")
    assert has_element?(view, "input[name=q][value=France]")
    render_patch(view, "/achievements/continent_europe?page=99")
    refute has_element?(view, "#native-achievement-dialog [data-selected-key]")
    render_patch(view, "/achievements/continent_europe")
    assert length(:sys.get_state(view.pid).socket.assigns.data.view.children) <= 12
    Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [user.id], log: false)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             render_patch(view, "/achievements/continent_europe?q=France")
  end

  @tag acceptance_close: true
  test "closing a selected card closes the browser dialog after its server patch", %{user: user} do
    {:ok, view, _} =
      live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

    render_click(view, "select_card", %{"key" => "country_fr"})
    assert_push_event(view, "close-dialog", %{id: "native-achievement-dialog"})
    assert has_element?(view, "#native-achievement-dialog [data-selected-key='country_fr']")
    render_click(view, "close_card", %{})
    assert_push_event(view, "close-dialog", %{id: "native-achievement-dialog"})
    refute has_element?(view, "#native-achievement-dialog [data-selected-key]")
  end

  @tag keyboard_card: true
  test "card dialog Escape and close return focus to the chosen card", %{user: user} do
    {:ok, view, html} =
      live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

    refute html =~ "RailsStimulus"
    refute html =~ "data-controller="
    render_click(view, "select_card", %{"key" => "country_fr"})

    assert has_element?(
             view,
             "#native-achievement-dialog[phx-window-keydown*='close_card'][phx-key='Escape']"
           )

    assert has_element?(
             view,
             "#native-achievement-country_fr[phx-keyup*='push_focus'][phx-key=Enter]"
           )

    refute has_element?(view, "#native-achievement-country_fr[phx-keydown]")
    assert has_element?(view, "#native-close-achievement-card[phx-click*='pop_focus']")
    assert has_element?(view, "#native-achievement-country_fr[phx-click*='push_focus']")
    render_click(view, "close_card", %{})
    refute has_element?(view, "#native-achievement-dialog [data-selected-key]")
  end

  test "connected render and reconnect do not celebrate twice", %{user: user} do
    earned =
      Map.new(
        Dawarich.Achievements.Registry.find("country_de").region_codes,
        &{&1, "2026-07-19T10:00:00Z"}
      )

    Repo.query!(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
      [user.id, %{"earned" => earned}],
      log: false
    )

    conn = NativeAchievementsUI.conn(user, "/achievements/country_de")

    assert [[nil]] =
             Repo.query!(
               "SELECT state->'celebrated' FROM achievement_progresses WHERE user_id=$1",
               [user.id],
               log: false
             ).rows

    {:ok, first, _} = live(conn)
    assert has_element?(first, ".ach-card-wrap--celebrate")
    {:ok, second, _} = live(NativeAchievementsUI.conn(user, "/achievements/country_de"))
    refute has_element?(second, ".ach-card-wrap--celebrate")

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
      [user.id],
      log: false
    )

    render_patch(view, "/achievements/country_de")
    refute has_element?(view, "#achievement-share-output[value]")

    Repo.query!(
      "UPDATE users SET encrypted_password='changed-00000000000000000000000' WHERE id=$1",
      [user.id],
      log: false
    )

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             render_click(view, "share_card", %{"enabled" => "true"})
  end

  @tag projection_refusal: true
  test "achievement selection after malformed URL refuses without a projection or effects", %{
    user: user
  } do
    Process.flag(:trap_exit, true)

    {:ok, view, _} =
      live(NativeAchievementsUI.conn(user, "/achievements/continent_europe?q=France"))

    render_patch(view, "/achievements/continent_europe?q[bad]=1")
    assert :sys.get_state(view.pid).socket.assigns.data == nil
    render_click(view, "lv:clear-flash", %{"key" => "alert"})

    {_, queries} =
      NativeAdminUI.queries(fn -> render_hook(view, "select_card", %{"key" => "country_fr"}) end)

    socket = :sys.get_state(view.pid).socket
    assert Process.alive?(view.pid)
    assert socket.assigns.data == nil
    assert socket.assigns.selected == nil
    assert socket.assigns.share_url == nil
    assert socket.assigns.flash["alert"]
    refute Enum.any?(queries, &String.match?(&1, ~r/\A\s*(INSERT|UPDATE|DELETE)\b/i))
    render_patch(view, "/achievements/continent_europe?q=France")
    render_click(view, "select_card", %{"key" => "country_fr"})
    assert :sys.get_state(view.pid).socket.assigns.selected.key == "country_fr"
  end
end
