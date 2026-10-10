defmodule DawarichWeb.AdminUserShowLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Admin.Users
  alias Dawarich.Test.NativeAdminUI
  @endpoint DawarichWeb.Endpoint

  setup do
    c = NativeAdminUI.setup!()
    Dawarich.JobsCase.start_oban(ShowUIOban, repo: Repo)
    previous = Application.get_env(:dawarich, Users)
    Application.put_env(:dawarich, Users, %{oban: ShowUIOban})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, Users, previous),
        else: Application.delete_env(:dawarich, Users)
    end)

    c
  end

  defp show(c), do: live(NativeAdminUI.conn(c.actor), "/settings/users/#{c.target.id}")

  test "target detail keeps redacted credentials out of session with observable mount budgets",
       c do
    {conn, static} =
      NativeAdminUI.queries(fn ->
        get(NativeAdminUI.conn(c.actor), "/settings/users/#{c.target.id}")
      end)

    {{:ok, view, html}, connected} = NativeAdminUI.queries(fn -> live(conn) end)
    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.native
    assert socket.assigns.target_user.encrypted_password == nil
    refute Map.has_key?(socket.assigns.target, :api_key)

    [token] =
      conn.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("[data-phx-session]")
      |> LazyHTML.attribute("data-phx-session")

    {:ok, decoded} = Phoenix.LiveView.Static.verify_token(@endpoint, token)
    assert String.contains?(inspect(decoded.session), c.target.api_key) == false

    assert has_element?(
             view,
             "#admin-user-copy[phx-hook=Clipboard][data-clipboard-text='#{c.target.api_key}']"
           )

    assert html =~ "synthet" <> "i"
    assert NativeAdminUI.labels(html) == []
    IO.puts("user show queries static=#{length(static)} connected=#{length(connected)}")
    assert length(static) in 1..18
    assert length(connected) in 1..11
    GenServer.stop(view.pid)
  end

  test "target rotation refreshes copy data and retires only the target key", c do
    {:ok, view, _} = show(c)
    before = Accounts.get(c.actor.id)
    render_hook(view, "rotate_api_key", %{})
    assert Accounts.get(c.target.id).api_key == c.target.api_key
    view |> element("#open-rotate") |> render_click()
    html = view |> element("#confirm-rotate") |> render_click()
    key = Accounts.get(c.target.id).api_key
    assert key != c.target.api_key
    assert Accounts.get(c.actor.id) == before

    assert NativeAdminUI.html(view)
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("#admin-user-copy")
           |> LazyHTML.attribute("data-clipboard-text") == [key]

    assert html =~
             NativeAdminUI.escaped("controllers.settings.users.api_key_has_been_regenerated")

    assert_push_event(view, "close-dialog", %{id: "rotate_api_key"})
  end

  test "password reset dispatch stores targeted digest and one sealed mail with Rails notice",
       c do
    {:ok, view, _} = show(c)
    html = view |> element("#send-password-reset") |> render_click()

    assert [[true]] =
             Repo.query!("SELECT reset_password_token IS NOT NULL FROM users WHERE id=$1", [
               c.target.id
             ]).rows

    assert [[nil]] =
             Repo.query!("SELECT reset_password_token FROM users WHERE id=$1", [c.actor.id]).rows

    assert [[args]] = Repo.query!("SELECT args FROM oban.oban_jobs").rows
    assert args["user_id"] == c.target.id
    assert args["kind"] == "reset_password_instructions"
    assert is_binary(args["sealed"])
    refute Map.has_key?(args, "token")
    assert String.contains?(html, args["digest"]) == false

    assert String.contains?(inspect(:sys.get_state(view.pid), limit: :infinity), args["digest"]) ==
             false

    assert html =~
             NativeAdminUI.escaped(
               "controllers.settings.users.password_reset_email_has_been_sent"
             )
  end

  test "accepted repeated security events publish one action per page", c do
    {:ok, view, _} = show(c)
    render_hook(view, "open_rotate", %{})
    render_hook(view, "rotate_api_key", %{})
    key = Accounts.get(c.target.id).api_key
    render_patch(view, "/settings/users/#{c.target.id}?panel=security")
    render_hook(view, "open_rotate", %{})
    render_hook(view, "rotate_api_key", %{})
    assert Accounts.get(c.target.id).api_key == key
    render_hook(view, "send_password_reset", %{})
    render_hook(view, "send_password_reset", %{})
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
    assert has_element?(view, "#send-password-reset[disabled]")
  end

  test "failed security effects unlock explicit retry", c do
    {:ok, view, _} = show(c)

    Application.put_env(:dawarich, Users, %{
      oban: ShowUIOban,
      enqueue: fn _ -> {:error, :failed} end
    })

    assert render_hook(view, "send_password_reset", %{}) =~
             NativeAdminUI.escaped("controllers.application.admin_action_failed")

    refute has_element?(view, "#send-password-reset[disabled]")
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    Application.put_env(:dawarich, Users, %{oban: ShowUIOban})
    render_hook(view, "send_password_reset", %{})
    assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[1]]
  end

  test "detail events params and info refuse revoked actors or a deleted target before effects",
       c do
    for reason <- [:demotion, :salt, :deletion],
        event <- [:rotate_api_key, :send_password_reset, :open_rotate, :params, :info] do
      Repo.query!(
        "UPDATE users SET admin=true,deleted_at=NULL,encrypted_password=$2 WHERE id=$1",
        [c.actor.id, c.actor.encrypted_password],
        log: false
      )

      {:ok, view, _} = show(c)
      if event == :rotate_api_key, do: render_hook(view, "open_rotate", %{})

      case reason do
        :demotion ->
          Repo.query!("UPDATE users SET admin=false WHERE id=$1", [c.actor.id])

        :salt ->
          Repo.query!(
            "UPDATE users SET encrypted_password='synthetic-changed-salt' WHERE id=$1",
            [c.actor.id]
          )

        :deletion ->
          Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [c.actor.id])
      end

      case event do
        :params -> render_patch(view, "/settings/users/#{c.target.id}?panel=security")
        :info -> send(view.pid, :navbar_refresh)
        _ -> render_hook(view, to_string(event), %{})
      end

      assert_redirect(view, if(reason == :demotion, do: "/", else: "/users/sign_in"))
      assert Accounts.get(c.target.id).api_key == c.target.api_key
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end

    Repo.query!(
      "UPDATE users SET admin=true,deleted_at=NULL,encrypted_password=$2 WHERE id=$1",
      [c.actor.id, c.actor.encrypted_password],
      log: false
    )

    for event <- ~w(rotate_api_key send_password_reset) do
      Repo.query!("UPDATE users SET deleted_at=NULL WHERE id=$1", [c.target.id])
      {:ok, view, _} = show(c)
      render_hook(view, "open_rotate", %{})
      Repo.query!("UPDATE users SET deleted_at=now() WHERE id=$1", [c.target.id])
      render_hook(view, event, %{})
      assert_redirect(view, "/settings/users")
      assert Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows == [[0]]
    end
  end

  test "clipboard key is render only and never carried in event replies or pushes", c do
    {:ok, view, _} = show(c)
    socket = :sys.get_state(view.pid).socket
    assert {:noreply, socket} = view.module.handle_event("open_rotate", %{}, socket)
    assert {:noreply, socket} = view.module.handle_event("rotate_api_key", %{}, socket)
    key = Accounts.get(c.target.id).api_key
    assert socket.assigns.target_user.api_key == key
    assert String.contains?(inspect(socket.private[:live_temp][:push_events] || []), key) == false
    assert {:noreply, socket} = view.module.handle_event("send_password_reset", %{}, socket)
    assert String.contains?(inspect(socket.private[:live_temp][:push_events] || []), key) == false
    GenServer.stop(view.pid)
  end

  test "open rotation dialog has exactly one label per control", c do
    {:ok, view, _} = show(c)
    view |> element("#open-rotate") |> render_click()
    socket = :sys.get_state(view.pid).socket
    html = rendered_to_string(view.module.render(Map.put(socket.assigns, :dialog_open, true)))
    assert Enum.count(LazyHTML.query(LazyHTML.from_fragment(html), "#rotate_api_key[open]")) == 1
    assert NativeAdminUI.labels(html) == []
  end
end
