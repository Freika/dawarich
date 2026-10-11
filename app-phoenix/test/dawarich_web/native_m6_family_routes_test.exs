defmodule DawarichWeb.NativeM6FamilyRoutesTest do
  use Dawarich.DataCase, async: true
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "family-route-#{id}@dawarich.test",
      api_key: "synthetic-family-route-key",
      settings: %{"timezone" => "UTC"}
    })

    at = NaiveDateTime.utc_now()

    Repo.insert_all("families", [
      %{id: id, creator_id: id, name: "Canonical family", created_at: at, updated_at: at}
    ])

    Repo.insert_all("family_memberships", [
      %{id: id, family_id: id, user_id: id, role: 0, created_at: at, updated_at: at}
    ])

    %{id: id}
  end

  test "canonical family route owns native consent and setup states and clears a removed resource",
       %{id: id} do
    {:ok, view, html} = live(RailsUser.signed_in(id) |> RailsUser.connecting_as(id), "/family")
    assert has_element?(view, "#native-family-map[phx-hook=Family]")
    assert has_element?(view, "#family-getting-started")
    assert has_element?(view, "#native-family-invite")
    assert String.contains?(html, "/native/app")
    refute String.contains?(html, "synthetic-family-route-key")
    refute has_element?(view, "[data-controller], [data-action], turbo-frame")

    view
    |> form("#native-family-sharing", sharing: %{enabled: "true", duration: "1h"})
    |> render_change()

    assert Dawarich.Accounts.get(id).settings["family"]["location_sharing"]["enabled"] == true

    Repo.transaction(fn ->
      Repo.query!("DELETE FROM family_memberships WHERE family_id=$1", [id], log: false)
      Repo.query!("DELETE FROM families WHERE id=$1", [id], log: false)
    end)

    render_hook(view, "map:ready", %{})
    refute has_element?(view, "#family-shell")
    assert_push_event(view, "map:clear", %{code: "not_found"})
    assert :sys.get_state(view.pid).socket.assigns.page_title == nil
  end

  test "idle Family server timer clears expired or withdrawn consent and ignores stale timer tokens",
       %{id: id} do
    expires = DateTime.add(DateTime.utc_now(), 10)

    settings = %{
      "family" => %{
        "location_sharing" => %{"enabled" => true, "expires_at" => DateTime.to_iso8601(expires)}
      }
    }

    Repo.query!("UPDATE users SET settings=settings || $2::jsonb WHERE id=$1", [id, settings],
      log: false
    )

    {:ok, view, _} = live(RailsUser.signed_in(id) |> RailsUser.connecting_as(id), "/family")
    lease = :sys.get_state(view.pid).socket.assigns.native_family_consent
    assert Process.read_timer(lease.timer) in 1..10000
    assert_push_event(view, "family:lease", %{milliseconds: milliseconds})
    assert milliseconds in 1..10000
    send(view.pid, :renew_family_admission)
    render(view)
    next = :sys.get_state(view.pid).socket.assigns.native_family_consent
    assert next.token != lease.token
    send(view.pid, {:native_family_consent, lease.token})
    render(view)
    refute_push_event(view, "family:clear", %{})

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,expires_at}',$2::jsonb) WHERE id=$1",
      [id, DateTime.to_iso8601(DateTime.add(DateTime.utc_now(), -1))],
      log: false
    )

    send(view.pid, {:native_family_consent, next.token})
    render(view)
    assert_push_event(view, "family:clear", %{code: "consent_expired"})
    assert_push_event(view, "map:invalidate", %{kind: "family"})
    assert has_element?(view, "#native-family-members", "Not sharing")
    assert Process.read_timer(next.timer) == false
    assert :sys.get_state(view.pid).socket.assigns.native_family_consent.milliseconds == 30000

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing}',$2::jsonb) WHERE id=$1",
      [id, %{"enabled" => true}],
      log: false
    )

    send(view.pid, :renew_family_admission)
    render(view)
    permanent = :sys.get_state(view.pid).socket.assigns.native_family_consent
    assert permanent.milliseconds == 30000

    Repo.query!(
      "UPDATE users SET settings=jsonb_set(settings,'{family,location_sharing,enabled}','false'::jsonb) WHERE id=$1",
      [id],
      log: false
    )

    send(view.pid, {:native_family_consent, permanent.token})
    render(view)
    assert_push_event(view, "family:clear", %{code: "consent_expired"})
    assert has_element?(view, "#native-family-members", "Not sharing")
    Repo.query!("DELETE FROM family_memberships WHERE user_id=$1", [id], log: false)
    send(view.pid, :renew_family_admission)
    render(view)
    assert :sys.get_state(view.pid).socket.assigns.native_family_consent == nil
  end

  test "canonical family envelopes refuse alternate transports and retain independent page and read routes",
       %{id: id} do
    for path <- ["/family.json", "/family?format=json"] do
      conn = RailsUser.signed_in(id) |> get(path)
      assert conn.status == 422
      assert conn.resp_body == ""
    end

    conn =
      RailsUser.signed_in(id)
      |> Plug.Conn.put_req_header("x-requested-with", "XMLHttpRequest")
      |> get("/family")

    assert conn.status == 422

    for {path, handler} <- [
          {"/family/new", DawarichWeb.FamiliesLive.Form},
          {"/family/edit", DawarichWeb.FamiliesLive.Form},
          {"/family/locations.json", DawarichWeb.FamilyLocations}
        ] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, "www.example.com")

      if handler == DawarichWeb.FamiliesLive.Form do
        assert {^handler, _, _, _} = route.phoenix_live_view
      else
        assert route.plug == handler
      end
    end

    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [id], log: false)
    conn = RailsUser.signed_in(id) |> RailsUser.connecting_as(id) |> get("/family")
    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
    {:ok, view, _} = live(conn)
    assert has_element?(view, "[role=alert]", "unauthorized")
    refute has_element?(view, "#family-shell")
  end
end
