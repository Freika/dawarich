defmodule DawarichWeb.PublicNativeAdmissionTest do
  use ExUnit.Case, async: true
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Repo, SharedLinks}
  alias Dawarich.Sharing.Public
  alias Dawarich.Test.SharingSeeds
  @endpoint DawarichWeb.Endpoint
  @id "a9500000-0000-4000-8000-000000000001"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    SharingSeeds.load!()
    %{now: DateTime.utc_now()}
  end

  for protection <- [:rotated, :added] do
    @protection protection
    test "bootstrap issuance refuses #{@protection} protection after the HTTP unlock check", c do
      old_phrase = if @protection == :rotated, do: "synthetic-old-unlock", else: ""

      Repo.query!(
        "UPDATE shared_links SET magic_phrase=$2 WHERE id=$1::text::uuid",
        [@id, old_phrase],
        log: false
      )

      link = SharedLinks.active(@id, c.now)
      name = "shared_link_" <> @id

      cookie =
        Dawarich.RailsCookies.encrypt(
          DawarichWeb.SharedLinkCookie.unlock_token(@id, old_phrase),
          name,
          Dawarich.RailsSecret.fetch(),
          DateTime.add(c.now, 1800)
        )

      conn = build_conn() |> put_req_cookie(name, cookie) |> DawarichWeb.PublicShareAuth.prepare()
      assert DawarichWeb.SharedLinkCookie.unlocked?(conn, link, c.now)

      Repo.query!(
        "UPDATE shared_links SET magic_phrase=$2 WHERE id=$1::text::uuid",
        [@id, "synthetic-new-unlock"],
        log: false
      )

      assert {:error, _} = DawarichWeb.PublicShareAuth.issue(conn, link, c.now)
      refute DawarichWeb.SharedLinkCookie.unlocked?(conn, SharedLinks.active(@id, c.now), c.now)
    end
  end

  defp grant(now) do
    link = SharedLinks.active(@id, now)
    {:ok, grant} = Public.grant(link, nil, now, DateTime.add(now, 1800))
    grant
  end

  defp open do
    conn = get(build_conn(), "/s/" <> @id)
    conn = put_private(conn, :live_view_connect_info, %{session: get_session(conn)})
    {:ok, view, _} = live(conn)
    {conn, view}
  end

  defp state(view), do: :sys.get_state(view.pid).socket.assigns

  test "expired revoked rotated and foreign-family public admission refuses before data load",
       c do
    for sql <- [
          "UPDATE shared_links SET expires_at=$2 WHERE id=$1::text::uuid",
          "UPDATE shared_links SET revoked_at=$2 WHERE id=$1::text::uuid",
          "UPDATE shared_links SET magic_phrase='rotated-public-probe' WHERE id=$1::text::uuid",
          "UPDATE shared_links SET settings='{\"audience\":\"family\",\"family_id\":\"1\"}' WHERE id=$1::text::uuid"
        ] do
      Repo.query!(
        "UPDATE shared_links SET expires_at=NULL,revoked_at=NULL,magic_phrase='',settings='{}' WHERE id=$1::text::uuid",
        [@id],
        log: false
      )

      g = grant(c.now)
      assert {:ok, page} = Public.read(g, c.now)
      refute Map.has_key?(page.link, :magic_phrase)
      args = if String.contains?(sql, "$2"), do: [@id, DateTime.to_naive(c.now)], else: [@id]
      Repo.query!(sql, args, log: false)
      assert {:error, _} = Public.read(g, c.now)
    end
  end

  test "foreign-family public bootstrap cannot mint a reader for a guest", c do
    Repo.query!(
      "UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid",
      [@id, %{"audience" => "family", "family_id" => "1"}],
      log: false
    )

    assert {:error, _} =
             Public.grant(SharedLinks.active(@id, c.now), nil, c.now, DateTime.add(c.now, 1800))

    assert (build_conn() |> get("/s/" <> @id)).status == 404
    assert SharingSeeds.view_count(@id) == 0
  end

  test "queued public update after revoke or phrase rotation clears old content before delivery" do
    for column <- ["revoked_at=NOW()", "magic_phrase='rotated-public-probe'"] do
      Repo.query!(
        "UPDATE shared_links SET revoked_at=NULL,magic_phrase='' WHERE id=$1::text::uuid",
        [@id],
        log: false
      )

      {_, view} = open()
      assert has_element?(view, "#native-public-share [data-public-content]")
      Repo.query!("UPDATE shared_links SET #{column} WHERE id=$1::text::uuid", [@id], log: false)
      send(view.pid, {:share_changed, @id, :queued})
      render(view)
      assert state(view).page == nil
      refute has_element?(view, "[data-public-content]")
      assert_push_event(view, "public-share-clear", %{})
    end
  end

  test "public expiry clears a silent connection and reconnect cannot revive it" do
    {_, view} = open()
    old = state(view).public_expiry
    send(view.pid, {:public_share_expiry, make_ref()})
    render(view)
    assert state(view).public_expiry.token == old.token

    Repo.query!("UPDATE shared_links SET expires_at=NOW() WHERE id=$1::text::uuid", [@id],
      log: false
    )

    send(view.pid, {:public_share_expiry, old.token})
    render(view)
    assert state(view).page == nil
    render_click(view, "public_reload", %{})
    assert state(view).page == nil
    assert build_conn() |> get("/s/" <> @id) |> response(404)
  end

  test "HTTP public bootstrap is session bound bounded read only and contains no secret state",
       c do
    {conn, view} = open()
    assigns = state(view)
    assert assigns.grant.expires_at <= DateTime.to_unix(c.now) + 1800
    refute Map.has_key?(assigns, :bootstrap)
    refute inspect(assigns) =~ "encrypted_password"
    before = SharingSeeds.view_count(@id)

    render_click(view, "sharing_create", %{
      "shared_link" => %{"magic_phrase" => "write-only-probe"}
    })

    render_click(view, "public_reload", %{})
    assert SharingSeeds.view_count(@id) == before
    refute inspect(state(view)) =~ "write-only-probe"
    token = conn.assigns.public_bootstrap
    bad = build_conn() |> put_private(:live_view_connect_info, %{session: %{}})

    {:ok, denied, _} =
      live_isolated(bad, DawarichWeb.PublicShareLive,
        session: %{"bootstrap" => token, "locale" => "en"}
      )

    assert state(denied).page == nil
    refute has_element?(denied, "[data-public-content]")
    Repo.query!("UPDATE users SET locked_at=NOW() WHERE id=9901", [], log: false)
    assert {:ok, _} = Public.read(assigns.grant, DateTime.utc_now())
    Repo.query!("UPDATE users SET deleted_at=NOW() WHERE id=9901", [], log: false)
    assert {:error, _} = Public.read(assigns.grant, DateTime.utc_now())
  end

  test "public connected viewer cannot upgrade identity or survive its session signout" do
    user = Dawarich.Test.RailsUser.session(9901)
    conn = Dawarich.Test.RailsUser.signed_in(9901, user) |> get("/s/" <> @id)
    assert conn.assigns.current_user.id == 9901
    session = Map.put(get_session(conn), "rails_user_id", 9901)
    {:ok, view, _} = live(put_private(conn, :live_view_connect_info, %{session: session}))
    assert has_element?(view, "[data-public-content]")
    token = conn.assigns.public_bootstrap

    for id <- [nil, 9902] do
      bad =
        build_conn()
        |> put_private(:live_view_connect_info, %{session: Map.put(session, "rails_user_id", id)})

      {:ok, denied, _} =
        live_isolated(bad, DawarichWeb.PublicShareLive, session: %{"bootstrap" => token})

      assert state(denied).page == nil
    end

    DawarichWeb.NotificationSession.signed_out(user)
    render(view)
    assert state(view).page == nil
    render_click(view, "public_reload", %{})
    assert state(view).page == nil
  end

  test "public bootstrap cannot outlive an earlier unlock or session cookie deadline", c do
    id = "a9500000-0000-4000-8000-000000000002"
    link = SharedLinks.active(id, c.now)
    due = DateTime.add(c.now, 30)
    name = "shared_link_" <> id

    cookie =
      Dawarich.RailsCookies.encrypt(
        DawarichWeb.SharedLinkCookie.unlock_token(id, link.magic_phrase),
        name,
        Dawarich.RailsSecret.fetch(),
        due
      )

    conn = build_conn() |> put_req_cookie(name, cookie) |> get("/s/" <> id)
    conn = put_private(conn, :live_view_connect_info, %{session: get_session(conn)})
    {:ok, view, _} = live(conn)
    assert state(view).grant.expires_at <= DateTime.to_unix(due)

    session_cookie =
      Dawarich.RailsCookies.encrypt(
        Dawarich.Test.RailsUser.session(9901),
        "_dawarich_session",
        Dawarich.RailsSecret.fetch(),
        due
      )

    conn =
      build_conn() |> put_req_cookie("_dawarich_session", session_cookie) |> get("/s/" <> @id)

    {:ok, signed, _} =
      live(
        put_private(conn, :live_view_connect_info, %{
          session: Map.put(get_session(conn), "rails_user_id", 9901)
        })
      )

    assert state(signed).grant.expires_at <= DateTime.to_unix(due)
  end
end
