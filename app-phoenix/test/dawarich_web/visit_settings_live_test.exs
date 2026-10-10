defmodule DawarichWeb.VisitSettingsLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.Translate

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)
    end)

    user =
      RailsUser.insert!(%{
        id: 7594,
        email: "visit-settings-live@dawarich.test",
        visits_redetected_at: nil,
        settings: %{"timezone" => "Europe/Berlin", "visit_min_points" => 3, "unrelated" => "kept"}
      })

    %{user: user}
  end

  defp conn_for(user), do: RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id)
  defp live_as(user), do: live(conn_for(user), "/settings/visits")

  defp stored(user),
    do: Repo.query!("SELECT settings FROM users WHERE id=$1", [user.id]).rows |> hd() |> hd()

  defp escaped(key),
    do:
      Translate.t("en", key, %{})
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

  defp redetections,
    do:
      Repo.query!(
        "SELECT count(*) FROM phoenix.rails_commands WHERE kind='visits.web_redetect' AND payload->>'user_id'=$1",
        ["7594"]
      ).rows

  test "saving the detection settings stores whole numbers and shows the notice", %{user: user} do
    {:ok, view, _html} = live_as(user)

    html =
      view
      |> form("#visit-detection-settings")
      |> render_submit(%{
        "settings" => %{
          "visit_radius_meters" => "150",
          "visit_min_points" => "4",
          "visit_min_duration_minutes" => "12.7"
        }
      })

    assert html =~ escaped("controllers.settings.visits.visit_detection_settings_updated")

    assert %{
             "visit_radius_meters" => 150,
             "visit_min_points" => 4,
             "visit_min_duration_minutes" => 12,
             "unrelated" => "kept"
           } = stored(user)

    assert has_element?(view, "input[name='settings[visit_radius_meters]'][value='150']")
  end

  test "a typed value stays in the field while the page re-renders", %{user: user} do
    {:ok, view, _html} = live_as(user)

    view
    |> form("#visit-detection-settings")
    |> render_change(%{"settings" => %{"visit_radius_meters" => "77"}})

    render_hook(view, "redetect", %{})

    assert has_element?(view, "input[name='settings[visit_radius_meters]'][value='77']")
    assert stored(user)["visit_radius_meters"] == nil
  end

  test "redetection asks first, queues once and the button stays off afterwards", %{user: user} do
    {:ok, view, _html} = live_as(user)
    button = "#redetect-visits"
    assert has_element?(view, button <> "[data-confirm][phx-disable-with]")
    refute has_element?(view, button <> "[disabled]")

    html = view |> element(button) |> render_click()

    assert html =~
             escaped(
               "controllers.visits.redetections.re_detection_queued_we_ll_notify_you_when_it_finishes"
             )

    assert redetections() == [[1]]
    assert has_element?(view, button <> "[disabled]")
  end

  test "a redetection that finished within the hour is refused with the Rails alert", %{
    user: user
  } do
    {:ok, view, _html} = live_as(user)
    Repo.query!("UPDATE users SET visits_redetected_at=now() WHERE id=$1", [user.id])

    assert render_hook(view, "redetect", %{}) =~
             escaped(
               "controllers.visits.redetections.re_detect_ran_recently_try_again_in_an_hour"
             )

    assert redetections() == [[0]]

    {:ok, view, _html} = live_as(user)
    assert has_element?(view, "#redetect-visits[disabled]")

    assert render(view) =~
             Translate.t("en", "settings.visits.redetect_panel.available_again_at", %{})
  end

  test "a time zone the database does not know falls back to the default zone", %{user: user} do
    Repo.query!(
      "UPDATE users SET settings = settings || '{\"timezone\":\"Unknown/Legacy\"}'::jsonb WHERE id=$1",
      [user.id]
    )

    {:ok, view, _html} = live_as(user)
    view |> element("#redetect-visits") |> render_click()
    assert redetections() == [[1]]

    Repo.query!("UPDATE users SET visits_redetected_at=now() WHERE id=$1", [user.id])
    {:ok, view, _html} = live_as(user)

    assert render(view) =~
             Translate.t("en", "settings.visits.redetect_panel.available_again_at", %{})
  end

  def handle_query(_event, _measurements, _meta, pid), do: send(pid, :query)

  defp queries(fun) do
    id = "visits-budget-#{System.unique_integer([:positive])}"
    :telemetry.attach(id, [:dawarich, :repo, :query], &__MODULE__.handle_query/4, self())
    result = fun.()
    :telemetry.detach(id)
    {result, drain(0)}
  end

  defp drain(n) do
    receive do
      :query -> drain(n + 1)
    after
      0 -> n
    end
  end

  test "the page stays within the Rails-era query budget", %{user: user} do
    {conn, static} = queries(fn -> get(conn_for(user), "/settings/visits") end)
    {_, connected} = queries(fn -> {:ok, _view, _html} = live(conn) end)

    assert static <= 9
    assert connected <= 6
  end

  test "signed-out settings uses the established Devise redirect" do
    conn = get(build_conn(), "/settings/visits")
    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
    assert conn.resp_body == ""
    [cookie] = get_resp_header(conn, "set-cookie")

    encrypted =
      cookie
      |> String.split(";", parts: 2)
      |> hd()
      |> String.replace_prefix("_dawarich_session=", "")

    {:ok, session} =
      Dawarich.RailsCookies.decrypt(
        encrypted,
        "_dawarich_session",
        Dawarich.RailsSecret.fetch(),
        DateTime.utc_now()
      )

    assert session["user_return_to"] == "/settings/visits"

    assert session["flash"]["flashes"]["alert"] ==
             "You need to sign in or sign up before continuing."
  end
end
