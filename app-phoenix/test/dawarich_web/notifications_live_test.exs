defmodule DawarichWeb.NotificationsLiveTest do
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2, get_session: 1]

  alias Dawarich.Notifications
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint
  @layout_headers "test/fixtures/layout/self_hosted_dark_en.json"
                  |> File.read!()
                  |> Jason.decode!()
                  |> Map.fetch!("headers")

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    %{user: RailsUser.insert!(%{id: 4101, email: "a5-live@dawarich.test"})}
  end

  defp live_as(user, path \\ "/notifications"),
    do: live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)

  test "a year-old notification renders in the user's zone on both pages" do
    user =
      RailsUser.insert!(%{
        id: 4103,
        email: "a5-zone@dawarich.test",
        settings: %{"timezone" => "Pacific/Kiritimati"}
      })

    now = NaiveDateTime.utc_now()

    Dawarich.Repo.insert_all("notifications", [
      %{
        id: 41_950,
        user_id: 4103,
        title: "Old",
        content: "x",
        kind: 0,
        created_at: NaiveDateTime.add(now, -400 * 86_400),
        updated_at: now
      }
    ])

    for path <- ["/notifications", "/notifications/41950"] do
      {:ok, _view, html} = live_as(user, path)
      assert html =~ "about 1 year ago"
    end
  end

  defp join_reply(conn, socket_session, mounts \\ 0) do
    html = Phoenix.ConnTest.response(conn, 200)
    session_token = html_attribute(html, "data-phx-session")
    static_token = html_attribute(html, "data-phx-static")
    {:ok, %{id: id}} = Phoenix.LiveView.Static.verify_token(@endpoint, session_token)
    ref = make_ref()
    from = {self(), ref}

    socket = %Phoenix.Socket{
      transport_pid: self(),
      serializer: Phoenix.LiveViewTest.ClientProxy,
      endpoint: @endpoint,
      private: %{connect_info: %{session: socket_session}},
      topic: "lv:" <> id,
      join_ref: "1"
    }

    {:ok, channel} = Phoenix.LiveView.Channel.start_link({@endpoint, from})
    Process.unlink(channel)

    send(
      channel,
      {Phoenix.Channel,
       %{
         "session" => session_token,
         "static" => static_token,
         "params" => %{"_mounts" => mounts},
         "url" => "http://www.example.com/notifications",
         "caller" => from
       }, from, socket}
    )

    assert_receive {^ref, reply}
    reply
  end

  defp rails_flash_conn(user, flashes) do
    session = RailsUser.session(user.id, %{"flash" => %{"discard" => [], "flashes" => flashes}})

    Phoenix.ConnTest.build_conn()
    |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> RailsUser.connecting_as(user.id)
  end

  defp lock(user),
    do:
      Dawarich.Repo.update_all(
        from(u in "users", where: u.id == ^user.id),
        set: [locked_at: NaiveDateTime.utc_now()]
      )

  defp consent(user),
    do:
      Dawarich.Repo.one(from(u in "users", where: u.id == ^user.id, select: u.changelog_consent))

  defp redirect_flash(%{flash: token}),
    do: Phoenix.LiveView.Utils.verify_flash(@endpoint, token)

  defp redirect_flash(_redirect), do: %{}

  defp html_attribute(html, name) do
    [_, value] = Regex.run(~r/#{name}="([^"]+)"/, html)
    value
  end

  defp rows(view),
    do:
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#notifications > div")
      |> Enum.count()

  test "the Rails user sees the page with the shared layout", %{user: user} do
    {:ok, _view, html} = live_as(user)

    assert html =~ ~s(<h1 class="text-3xl font-bold">Notifications</h1>)
    assert html =~ ~s(data-theme="dawarich-dark")
    assert html =~ "<title>Notifications | Dawarich</title>"
  end

  test "the page sends the security headers Rails pages send, and no CSP", %{user: user} do
    conn = get(RailsUser.signed_in(user.id), "/notifications")

    for {name, value} <- @layout_headers,
        do: assert(get_resp_header(conn, name) == List.wrap(value))

    assert get_resp_header(conn, "content-security-policy") == []
  end

  test "a stale socket session reloads while a readable ended Rails session redirects on connect",
       %{user: user} do
    conn = get(RailsUser.signed_in(user.id), "/notifications")
    socket_session = get_session(conn) |> Map.put("rails_user_id", nil)

    assert {:error, %{reason: "stale"}} = join_reply(conn, nil)
    assert {:error, %{redirect: %{to: "/users/sign_in"}}} = join_reply(conn, socket_session)

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(nil), "/notifications")
  end

  test "an owned GET route answers HEAD without a body", %{user: user} do
    conn = head(RailsUser.signed_in(user.id), "/notifications")

    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "inside the connected LiveView the footer is the one Rails renders", %{user: user} do
    System.put_env("SELF_HOSTED", "true")
    on_exit(fn -> System.delete_env("SELF_HOSTED") end)
    {rails, _meta} = Dawarich.Test.LayoutFixtures.load("self_hosted_dark_en")
    {:ok, view, _html} = live_as(user)

    assert Dawarich.Test.ParityHTML.fragment(render(view), "footer") ==
             Dawarich.Test.ParityHTML.fragment(rails, "footer")
  end

  test "the offered language follows the query of the latest patch", %{user: user} do
    {:ok, view, _html} =
      RailsUser.signed_in(user.id)
      |> RailsUser.connecting_as(user.id)
      |> Plug.Conn.put_req_header("accept-language", "de")
      |> live("/notifications?x[]=1&x[]=2")

    assert render_patch(view, "/notifications?page=2&x[]=1&x[]=2") =~
             ~s(href="/notifications?locale=de&amp;page=2&amp;x%5B%5D=1&amp;x%5B%5D=2")
  end

  test "a non-string page parameter renders page 1, not a crash", %{user: user} do
    Dawarich.Repo.insert_all("notifications", [
      %{
        id: 41_960,
        user_id: user.id,
        title: "Only one",
        content: "x",
        kind: 0,
        created_at: NaiveDateTime.utc_now(:second),
        updated_at: NaiveDateTime.utc_now(:second)
      }
    ])

    {:ok, view, _html} = live_as(user, "/notifications?page[]=2")
    assert has_element?(view, "#notification_41960")
  end

  describe "the index" do
    setup %{user: user} do
      now = NaiveDateTime.add(NaiveDateTime.utc_now(:second), -60)

      Dawarich.Repo.insert_all(
        "notifications",
        for n <- 1..22 do
          %{
            id: 41_000 + n,
            user_id: user.id,
            title: "N #{n}",
            kind: if(n == 22, do: 2, else: 0),
            content:
              if(n == 22, do: "B9 safe detail <script>window.b9Xss=true</script>", else: "c"),
            read_at: if(n <= 3, do: now),
            created_at: NaiveDateTime.add(now, -n * 60),
            updated_at: now
          }
        end
      )

      :ok
    end

    test "lists 20, paginates by patch, links each title to its page", %{user: user} do
      {:ok, view, _html} = live_as(user)
      assert rows(view) == 20

      assert has_element?(
               view,
               ~s(#notification_41004 a[href="/notifications/41004"].text-blue-600),
               "N 4"
             )

      assert has_element?(view, ~s(#notification_41001 a.text-gray-600), "N 1")

      view |> element(~s(a[rel="next"]), "»") |> render_click()
      assert_patch(view, "/notifications?page=2")
      assert rows(view) == 2
    end

    test "mark all and delete all show Rails' notices and patch to /notifications", %{user: user} do
      {:ok, view, _html} = live_as(user)
      assert has_element?(view, "a", "Mark all as read")
      render_patch(view, "/notifications?page=2")

      render_click(view, "mark_all_as_read", %{})
      assert_patch(view, "/notifications")
      assert render(view) =~ "All notifications marked as read."
      refute has_element?(view, "a", "Mark all as read")

      render_patch(view, "/notifications?page=2")
      view |> element("a", "Delete all") |> render_click()
      assert_patch(view, "/notifications")
      assert render(view) =~ "All notifications where successfully destroyed."
      assert rows(view) == 0
      refute has_element?(view, "a", "Delete all")
    end

    test "without a socket every action posts to the Rails endpoint with a token Rails accepts",
         %{user: user} do
      session = RailsUser.session(user.id)

      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

      index = conn |> get("/notifications") |> html_response(200) |> LazyHTML.from_document()

      for path <- ~w(/notifications/mark_as_read /notifications/destroy_all) do
        assert index
               |> LazyHTML.query(~s(a[href="#{path}"][data-turbo-method="post"]))
               |> Enum.count() == 1
      end

      assert index
             |> LazyHTML.query(~s(meta[name="csrf-param"][content="authenticity_token"]))
             |> Enum.count() == 1

      [token] =
        index |> LazyHTML.query(~s(meta[name="csrf-token"])) |> LazyHTML.attribute("content")

      assert RailsCsrf.valid?(session, token)

      show = conn |> get("/notifications/41022") |> html_response(200) |> LazyHTML.from_document()

      form =
        LazyHTML.query(show, ~s(form.button_to[method="post"][action="/notifications/41022"]))

      assert form |> LazyHTML.query(~s(input[name="_method"][value="delete"])) |> Enum.count() ==
               1

      [token] =
        form
        |> LazyHTML.query(~s(input[name="authenticity_token"]))
        |> LazyHTML.attribute("value")

      assert RailsCsrf.valid?(session, token)
    end

    test "time ago is read against the clock of the latest page view, not the first mount", %{
      user: user
    } do
      {:ok, view, _html} = live_as(user)

      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns.now, DateTime.add(DateTime.utc_now(), -3600))
      end)

      assert render_patch(view, "/notifications?page=2") =~ "22 minutes ago"
    end

    test "a Rails flash comes back on the first connect only, never on a reconnect", %{user: user} do
      conn = get(rails_flash_conn(user, %{"notice" => "From Rails"}), "/notifications")
      socket_session = conn |> get_session() |> Map.put("rails_user_id", user.id)

      assert {:ok, first} = join_reply(conn, socket_session, 0)
      assert inspect(first, limit: :infinity) =~ "From Rails"
      assert {:ok, again} = join_reply(conn, socket_session, 1)
      refute inspect(again, limit: :infinity) =~ "From Rails"
    end

    test "an event from an account locked since the page opened is not carried out", %{user: user} do
      {:ok, index, _html} = live_as(user)
      {:ok, show, _html} = live_as(user, "/notifications/41022")
      lock(user)

      assert {:error, {:redirect, %{to: "/notifications"}}} =
               index |> element("a", "Delete all") |> render_click()

      assert {:error, {:redirect, %{to: "/notifications/41022"}}} =
               show |> form(~s(form.button_to[action="/notifications/41022"])) |> render_submit()

      assert Notifications.page(user.id, 1).notifications |> length() == 20
    end

    test "a notification deleted before the socket connects reloads into the 404 without a crash",
         %{user: user} do
      conn =
        get(
          RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id),
          "/notifications/41022"
        )

      Notifications.delete(user.id, 41_022)

      assert {:error, {:redirect, %{to: "/notifications/41022"}}} = live(conn)
    end

    test "a not-found redirect URI-encodes an id needing escaping", %{user: user} do
      conn =
        get(
          RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id),
          "/notifications/41022%20"
        )

      Notifications.delete(user.id, 41_022)

      assert {:error, {:redirect, %{to: "/notifications/41022%20"}}} = live(conn)
    end

    test "destroying a notification removed meanwhile answers the 404, not the notice", %{
      user: user
    } do
      {:ok, view, _html} = live_as(user, "/notifications/41022")
      Notifications.delete(user.id, 41_022)

      assert {:error, {:redirect, %{to: "/notifications/41022"} = redirect}} =
               view |> form(~s(form.button_to[action="/notifications/41022"])) |> render_submit()

      assert redirect_flash(redirect) == %{}
    end

    test "opening a notification marks it read and shows safe content with the error hint", %{
      user: user
    } do
      {:ok, view, html} = live_as(user, "/notifications/41022")
      assert html =~ ~s(id="detail_notification_41022")
      assert html =~ "B9 safe detail"
      refute html =~ "<script>window.b9Xss"
      assert html =~ "Github Issues"
      assert has_element?(view, "#detail_notification_41022 a.text-gray-600")
      assert Dawarich.Notifications.get(user.id, 41_022).read_at
    end

    test "destroying redirects to the list with Rails' notice", %{user: user} do
      {:ok, view, _html} = live_as(user, "/notifications/41022")

      assert {:error, {:redirect, %{to: "/notifications"} = redirect}} =
               view |> form(~s(form.button_to[action="/notifications/41022"])) |> render_submit()

      assert redirect_flash(redirect) == %{"notice" => "Notification was successfully destroyed."}
      assert Dawarich.Notifications.get(user.id, 41_022) == nil
    end

    test "another user's notification answers Rails' 404 page", %{user: user} do
      RailsUser.insert!(%{id: 4102, email: "a5-live-other@dawarich.test"})
      now = NaiveDateTime.utc_now()

      Dawarich.Repo.insert_all("notifications", [
        %{
          id: 41_900,
          user_id: 4102,
          title: "x",
          content: "x",
          kind: 0,
          created_at: now,
          updated_at: now
        }
      ])

      {404, _headers, body} =
        assert_error_sent(404, fn -> get(RailsUser.signed_in(user.id), "/notifications/41900") end)

      assert body == File.read!(Dawarich.RailsRoot.join("public/404.html"))
    end

    test "a Rails flash is cleared through LiveView like a LiveView flash", %{user: user} do
      conn =
        Phoenix.ConnTest.build_conn()
        |> Phoenix.ConnTest.put_req_cookie(
          "_dawarich_session",
          RailsUser.cookie(
            RailsUser.session(user.id, %{
              "flash" => %{"discard" => [], "flashes" => %{"notice" => "From Rails"}}
            })
          )
        )

      {:ok, view, _html} = live(RailsUser.connecting_as(conn, user.id), "/notifications")
      assert render(view) =~ "From Rails"
      view |> element("#flash-messages [role=alert] button") |> render_click()
      refute render(view) =~ "From Rails"
    end
  end

  describe "the navbar" do
    setup %{user: user} do
      now = NaiveDateTime.utc_now()

      Dawarich.Repo.insert_all(
        "notifications",
        for(
          n <- 1..2,
          do: %{
            user_id: user.id,
            title: "Nav #{n}",
            content: "c",
            kind: 0,
            created_at: now,
            updated_at: now
          }
        )
      )

      :ok
    end

    test "shows the unread badge, refreshes it on each tick and after mark all", %{user: user} do
      {:ok, view, _html} = live_as(user)
      assert has_element?(view, "#notifications-badge", "2")
      now = NaiveDateTime.utc_now()

      Dawarich.Repo.insert_all("notifications", [
        %{
          user_id: user.id,
          title: "Nav 3",
          content: "c",
          kind: 0,
          created_at: now,
          updated_at: now
        }
      ])

      send(view.pid, :navbar_refresh)
      assert has_element?(view, "#notifications-badge", "3")
      assert has_element?(view, "#notifications-list a", "Nav 3")
      view |> element("a", "Mark all as read") |> render_click()
      assert has_element?(view, "#notifications-badge.hidden")
    end

    test "the changelog prompt saves the reader's choice", %{user: user} do
      System.put_env("SELF_HOSTED", "true")
      on_exit(fn -> System.delete_env("SELF_HOSTED") end)
      {:ok, view, _html} = live_as(user)
      assert has_element?(view, "h3", "Stay up to date?")
      render_submit(view, "changelog_consent", %{"decision" => "maybe"})
      assert has_element?(view, "h3", "Stay up to date?")
      assert consent(user) == nil
      render_submit(view, "changelog_consent", %{"decision" => "declined"})
      refute has_element?(view, "h3", "Stay up to date?")
      assert Dawarich.Accounts.get(user.id).changelog_consent == 0
    end

    test "a choice from an account locked since the page opened is not saved", %{user: user} do
      System.put_env("SELF_HOSTED", "true")
      on_exit(fn -> System.delete_env("SELF_HOSTED") end)
      {:ok, view, _html} = live_as(user)
      lock(user)

      assert {:error, {:redirect, %{to: "/notifications"}}} =
               render_submit(view, "changelog_consent", %{"decision" => "granted"})

      assert consent(user) == nil
    end
  end
end
