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
end
