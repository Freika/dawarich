defmodule Dawarich.Visits.WebSettingsTest do
  use Dawarich.IngestCase
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  @endpoint DawarichWeb.Endpoint
  alias Dawarich.Visits.WebSettings
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-03 10:00:00Z]

  describe "writes" do
    setup do
      alias Dawarich.ScratchRepo
      Dawarich.JobsCase.reset!(ScratchRepo)

      ScratchRepo.insert_all("users", [
        %{
          id: 8890,
          email: "a8-settings-write@dawarich.test",
          encrypted_password: "synthetic",
          settings: %{
            "timezone" => "Europe/Berlin",
            "visit_radius_meters" => 100,
            "visit_min_points" => 3,
            "unrelated" => "kept"
          },
          visits_redetected_at: nil,
          created_at: ~N[2026-10-03 09:00:00],
          updated_at: ~N[2026-10-03 09:00:00]
        }
      ])

      :ok
    end

    test "partial save preserves unrelated and omitted detection settings" do
      repo = Dawarich.ScratchRepo

      assert {:ok, saved} =
               WebSettings.save(
                 repo,
                 8890,
                 %{"visit_radius_meters" => "75", "unknown" => "discard"},
                 @now
               )

      assert saved == %{
               "timezone" => "Europe/Berlin",
               "visit_radius_meters" => 75,
               "visit_min_points" => 3,
               "unrelated" => "kept"
             }

      assert WebSettings.load(repo, 8890).settings == saved

      assert [[~N[2026-10-03 10:00:00.000000]]] =
               repo.query!("SELECT updated_at FROM users WHERE id=8890").rows
    end

    test "settings persist raw Ruby integers and clamp only on display" do
      repo = Dawarich.ScratchRepo

      assert {:ok, saved} =
               WebSettings.save(
                 repo,
                 8890,
                 %{
                   "visit_radius_meters" => "nonsense",
                   "visit_min_points" => "-2",
                   "visit_min_duration_minutes" => "0"
                 },
                 @now
               )

      assert saved["visit_radius_meters"] == 0
      assert saved["visit_min_points"] == -2
      assert saved["visit_min_duration_minutes"] == 0
      policy = Dawarich.Visits.Settings.policy(saved)
      assert %{stay_radius_m: 5, min_points: 2, min_dwell_s: 60} = policy
      assert {:replay, _} = WebSettings.save(repo, 8890, %{"visit_radius_meters" => ["75"]}, @now)
      assert WebSettings.load(repo, 8890).settings == saved
    end

    test "fresh cooldown returns Rails 429 and produces no command" do
      repo = Dawarich.ScratchRepo

      repo.query!("UPDATE users SET visits_redetected_at=$1 WHERE id=8890", [
        ~N[2026-10-03 09:30:00]
      ])

      assert {:cooldown, 429} = WebSettings.redetect(repo, 8890, @now, "en")
      assert repo.query!("SELECT id FROM phoenix.rails_commands").rows == []

      assert [[~N[2026-10-03 09:30:00.000000]]] =
               repo.query!("SELECT visits_redetected_at FROM users WHERE id=8890").rows
    end

    test "allowed redetection queues once without stamping controller cooldown" do
      repo = Dawarich.ScratchRepo

      repo.query!("UPDATE users SET visits_redetected_at=$1 WHERE id=8890", [
        ~N[2026-10-03 09:00:00]
      ])

      assert {:ok, _} = WebSettings.redetect(repo, 8890, @now, "en")

      assert [
               [
                 "visits.web_redetect",
                 %{"user_id" => 8890, "locale" => "en", "timezone" => "Europe/Berlin"}
               ]
             ] =
               repo.query!("SELECT kind,payload FROM phoenix.rails_commands").rows

      assert [[~N[2026-10-03 09:00:00.000000]]] =
               repo.query!("SELECT visits_redetected_at FROM users WHERE id=8890").rows
    end
  end

  setup do
    row =
      RailsUser.insert!(%{
        id: 8890,
        email: "a8-settings@dawarich.test",
        settings: %{"timezone" => "Europe/Berlin"}
      })

    %{user: Dawarich.Accounts.get(row.id)}
  end

  defp mounted(user),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), "/settings/visits")

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
      {:ok, view, _html} = mounted(user)

      for {name, value} <-
            Enum.zip(~w(visit_radius_meters visit_min_points visit_min_duration_minutes), values) do
        assert has_element?(view, "#settings_#{name}[value='#{value}']"), name
      end
    end

    Repo.query!("UPDATE users SET settings = $2, visits_redetected_at = $3 WHERE id = $1", [
      user.id,
      %{"timezone" => "Europe/Berlin", "visit_radius_meters" => 231},
      DateTime.utc_now() |> DateTime.add(-10) |> DateTime.to_naive()
    ])

    {:ok, view, body} = mounted(user)

    assert body =~ ">Visit detection | Dawarich</title>"
    assert has_element?(view, "#settings_visit_radius_meters[value='231']")
    assert has_element?(view, "#redetect-visits[disabled]")
    assert has_element?(view, "#settings-navigation a[href='/settings/visits'].tab-active")
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
    refute WebSettings.page(user, snapshot, @now, true).restricted
  end
end
