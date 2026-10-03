defmodule Dawarich.Visits.WebSettingsTest do
  use Dawarich.IngestCase
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  @endpoint DawarichWeb.Endpoint
  alias Dawarich.Visits.WebSettings
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-03 10:00:00Z]

  setup do
    row =
      RailsUser.insert!(%{
        id: 8890,
        email: "a8-settings@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: Dawarich.Accounts.get(row.id)}
  end

  defp html(user, page) do
    render_component(
      &DawarichWeb.SettingsLive.Visits.render/1,
      Map.merge(page, %{
        current_user: user,
        locale: "en",
        self_hosted: false,
        rails_csrf_token: "a8-synthetic-csrf",
        two_factor: false
      })
    )
  end

  test "settings defaults and clamped display values match safe settings", %{user: user} do
    for {settings, values} <- [
          {%{}, [100, 3, 5]},
          {%{
             "visit_radius_meters" => 900,
             "visit_min_points" => -1,
             "visit_min_duration_minutes" => 80
           }, [500, 2, 60]},
          {%{
             "visit_radius_meters" => "no",
             "visit_min_points" => "no",
             "visit_min_duration_minutes" => "no"
           }, [5, 2, 1]}
        ] do
      Repo.query!("UPDATE users SET settings = $2 WHERE id = $1", [user.id, settings])
      snapshot = WebSettings.load(Repo, user.id)
      page = WebSettings.page(user, snapshot, @now, false)
      body = html(user, page)

      for {name, value} <-
            Enum.zip(~w(visit_radius_meters visit_min_points visit_min_duration_minutes), values) do
        assert [Integer.to_string(value)] ==
                 body
                 |> LazyHTML.from_document()
                 |> LazyHTML.query("#settings_" <> name)
                 |> LazyHTML.attribute("value")
      end

      assert body =~ "action=\"/settings/visits\""
      assert body =~ "name=\"_method\" value=\"patch\""
      assert body =~ "data-turbo-confirm"
      assert page.rails_js
    end

    assert WebSettings.page(user, %{settings: [], last_redetected: nil}, @now, false) == :rails

    assert WebSettings.page(
             user,
             %{settings: %{"timezone" => "Unknown/Legacy"}, last_redetected: nil},
             @now,
             false
           ) == :rails

    Repo.query!("UPDATE users SET settings = $2, visits_redetected_at = $3 WHERE id = $1", [
      user.id,
      %{"timezone" => "Europe/Berlin", "visit_radius_meters" => 231},
      DateTime.utc_now() |> DateTime.add(-10) |> DateTime.to_naive()
    ])

    {:ok, view, body} =
      live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/settings/visits",
        on_error: [duplicate_id: :warn]
      )

    assert body =~ "<title>Visit detection | Dawarich</title>"
    assert has_element?(view, "#settings_visit_radius_meters[value='231']")
    assert has_element?(view, "form[action='/visits/redetections'] button[disabled]")
    assert has_element?(view, "form[action='/settings/visits'] input[name='authenticity_token']")
    assert has_element?(view, "#settings-navigation a[href='/settings/visits'].tab-active")

    Repo.query!("UPDATE users SET settings = $2 WHERE id = $1", [
      user.id,
      %{"timezone" => "Unknown/Legacy"}
    ])

    refute DawarichWeb.A8Gate.settings?(RailsUser.signed_in(user.id), %{})
  end

  test "cooldown is strictly inside one hour and displays request-zone short time", %{user: user} do
    snapshot = WebSettings.load(Repo, user.id)

    for {last, cooldown} <- [
          {nil, false},
          {~N[2026-10-03 09:00:00], false},
          {~N[2026-10-03 09:00:01], true}
        ] do
      Repo.query!("UPDATE users SET visits_redetected_at = $2 WHERE id = $1", [user.id, last])
      fresh = WebSettings.load(Repo, user.id)

      assert (is_nil(last) and is_nil(fresh.last_redetected)) or
               NaiveDateTime.compare(fresh.last_redetected, last) == :eq

      page = WebSettings.page(user, fresh, @now, false)
      assert page.cooldown == cooldown
      assert html(user, page) =~ "btn-disabled" == cooldown
      if cooldown, do: assert(page.available_at == "03 Oct 12:00")
    end

    page =
      WebSettings.page(
        user,
        %{snapshot | last_redetected: ~N[2026-10-25 00:30:00]},
        ~U[2026-10-25 01:00:00Z],
        false
      )

    assert page.available_at == "25 Oct 02:30"
  end

  test "Lite hint respects inherited family access", %{user: user} do
    user = %{user | plan: 0}
    snapshot = WebSettings.load(Repo, user.id)
    assert WebSettings.page(user, snapshot, @now, false).restricted
    owner = RailsUser.insert!(%{id: 8891, email: "a8-owner@dawarich.test", plan: 2})
    stamp = DateTime.to_naive(@now)

    {1, [%{id: family}]} =
      Repo.insert_all(
        "families",
        [%{name: "Synthetic family", creator_id: owner.id, created_at: stamp, updated_at: stamp}],
        returning: [:id]
      )

    Repo.insert_all("family_memberships", [
      %{family_id: family, user_id: user.id, role: 1, created_at: stamp, updated_at: stamp}
    ])

    page = WebSettings.page(user, snapshot, @now, false)
    refute page.restricted
    refute html(user, page) =~ "12 months"
    refute WebSettings.page(user, snapshot, @now, true).restricted
  end
end
