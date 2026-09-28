defmodule DawarichWeb.NotificationsLiveTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn, only: [get_resp_header: 2, get_session: 1]

  alias Dawarich.Test.RailsUser

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

  defp join_reply(conn, socket_session) do
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
         "params" => %{"_mounts" => 0},
         "url" => "http://www.example.com/notifications",
         "caller" => from
       }, from, socket}
    )

    assert_receive {^ref, reply}
    reply
  end

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

      view |> element("a", "Mark all as read") |> render_click()
      assert_patch(view, "/notifications")
      assert render(view) =~ "All notifications marked as read."
      refute has_element?(view, "a", "Mark all as read")

      view |> element("a", "Delete all") |> render_click()
      assert render(view) =~ "All notifications where successfully destroyed."
      assert rows(view) == 0
      refute has_element?(view, "a", "Delete all")
    end
  end
end
