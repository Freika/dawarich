defmodule DawarichWeb.SharingNativeEventsTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint

  setup do
    user = FrameSeeds.seed_management!("hub_empty_live_en")
    saved = Map.new(~w(SELF_HOSTED DAWARICH_RAILS), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "true")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      for {k, v} <- saved, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    %{user: user}
  end

  defp open(user, path \\ "/share_links/hub") do
    live(RailsUser.signed_in(user.id) |> RailsUser.connecting_as(user.id), path)
  end

  defp snapshot(view), do: :sys.get_state(view.pid).socket.assigns

  defp attrs(phrase \\ "") do
    %{
      "shared_link" => %{
        "magic_phrase" => phrase,
        "expires_at" => "",
        "settings" => %{"show_route" => "1"}
      }
    }
  end

  test "native hub creates revokes rotates and switches resources without frame requests", c do
    {:ok, view, _} = open(c.user)
    assert has_element?(view, "#native-sharing form[phx-submit=sharing_create]")
    refute has_element?(view, "turbo-frame, [data-controller]")
    render_submit(view, "sharing_create", attrs())

    [[id]] =
      Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.user.id], log: false).rows

    assert has_element?(view, "[data-share-id='#{id}']")
    render_click(view, "sharing_prepare", %{"action" => "regenerate"})
    render_click(view, "sharing_confirm", %{})

    [[new_id]] =
      Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.user.id], log: false).rows

    refute new_id == id
    assert snapshot(view).confirmation == nil
    render_click(view, "sharing_confirm", %{})

    assert Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.user.id],
             log: false
           ).rows == [[new_id]]

    render_click(view, "sharing_prepare", %{"action" => "regenerate_phrase"})
    render_click(view, "sharing_confirm", %{})
    render_patch(view, "/share_links/hub?tab=timeline")
    assert snapshot(view).resource.type == :timeline

    render_submit(view, "sharing_create", %{
      "shared_link" => %{
        "magic_phrase" => "",
        "expires_at" => "",
        "start_date" => "2026-10-01",
        "end_date" => "2026-10-03"
      }
    })

    render_click(view, "sharing_prepare", %{"action" => "revoke"})
    render_click(view, "sharing_confirm", %{})
    assert has_element?(view, "form[phx-submit=sharing_create]")
    render_patch(view, "/share_links/hub?tab=shared")
    assert snapshot(view).tab == "shared"
    assert has_element?(view, "[data-share-id='#{new_id}']")
  end

  test "phrase submission reveal and failures leave no phrase in LiveView state or crash logs",
       c do
    {:ok, view, _} = open(c.user)
    secret = "opaque-native-test-phrase"

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        render_submit(view, "sharing_create", attrs(secret))
      end)

    refute log =~ secret

    crash_log =
      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, pid} =
          GenServer.start(Dawarich.Test.NativeSharingCrash, %{socket: %{assigns: snapshot(view)}})

        ref = Process.monitor(pid)

        send(pid, %Phoenix.Socket.Message{
          topic: "lv:native-probe",
          event: "event",
          payload: %{
            "event" => "sharing_create",
            "type" => "form",
            "value" => "shared_link%5Bmagic_phrase%5D=#{secret}"
          }
        })

        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
        Logger.flush()
      end)

    assert crash_log =~ "native sharing event failure"
    refute crash_log =~ secret
    refute inspect(snapshot(view)) =~ secret
    refute render(view) =~ secret

    [[id]] =
      Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1", [c.user.id], log: false).rows

    session = RailsUser.session(c.user.id)
    conn = build_conn() |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    csrf = DawarichWeb.RailsCsrf.masked_token(session)
    generated = conn |> put_req_header("x-csrf-token", csrf) |> get("/native/sharing/phrase")
    assert generated.status == 200
    assert length(String.split(generated.resp_body, "-")) == 3
    assert get_resp_header(generated, "cache-control") == ["no-store"]
    denied = get(conn, "/native/sharing/#{id}/phrase")
    assert denied.status == 403
    revealed = conn |> put_req_header("x-csrf-token", csrf) |> get("/native/sharing/#{id}/phrase")
    assert response(revealed, 200) == secret
    assert get_resp_header(revealed, "cache-control") == ["no-store"]
    render_click(view, "sharing_prepare", %{"action" => "revoke"})
    render_click(view, "sharing_confirm", %{})
    render_submit(view, "sharing_create", attrs(String.duplicate(secret, 30)))
    assert has_element?(view, "[role=alert]")
    refute inspect(snapshot(view)) =~ secret
    refute render(view) =~ secret

    render_submit(view, "sharing_create", %{
      "shared_link" => %{
        "magic_phrase" => secret,
        "name" => %{"magic_phrase" => secret},
        "settings" => %{"show_route" => %{"magic_phrase" => secret}}
      }
    })

    refute inspect(snapshot(view)) =~ secret
  end

  test "native sharing rejects foreign targets and stale identity before effects", c do
    {:ok, view, _} = open(c.user)
    render_submit(view, "sharing_create", attrs())

    before =
      Repo.query!("SELECT id,revoked_at FROM shared_links ORDER BY id", [], log: false).rows

    render_click(view, "sharing_prepare", %{
      "action" => "revoke",
      "id" => Ecto.UUID.generate()
    })

    assert snapshot(view).confirmation == nil
    render_click(view, "sharing_confirm", %{})

    assert Repo.query!("SELECT id,revoked_at FROM shared_links ORDER BY id", [], log: false).rows ==
             before

    Repo.query!(
      "UPDATE users SET encrypted_password=$1 WHERE id=$2",
      [String.duplicate("x", 60), c.user.id],
      log: false
    )

    send(view.pid, {:domain_changed, c.user.id, :sharing})
    assert_redirect(view, "/users/sign_in")

    assert Repo.query!("SELECT id,revoked_at FROM shared_links ORDER BY id", [], log: false).rows ==
             before
  end

  test "debug SQL logs from native share creation and phrase rotation never carry the phrase",
       c do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
    {:ok, view, _} = open(c.user)
    secret = "opaque-debug-sql-phrase"

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        render_submit(view, "sharing_create", attrs(secret))
        render_click(view, "sharing_prepare", %{"action" => "regenerate_phrase"})
        render_click(view, "sharing_confirm", %{})
        Logger.flush()
      end)

    [[rotated]] =
      Repo.query!("SELECT magic_phrase FROM shared_links WHERE user_id=$1", [c.user.id],
        log: false
      ).rows

    refute rotated == secret
    assert log =~ "INSERT INTO shared_links"
    assert log =~ "UPDATE shared_links SET magic_phrase"
    refute log =~ secret
    refute log =~ rotated
  end

  test "debug SQL error logs and crash reports from phrase-bearing writes never carry the phrase" do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)
    secret = "opaque-debug-error-phrase"
    sql = "UPDATE shared_links SET magic_phrase = $1 WHERE id = $2::text::uuid"

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        assert {:error, _} = Repo.query(sql, [secret, "not-a-share"])
        {:ok, pid} = Task.start(fn -> Repo.query!(sql, [secret, "not-a-share"]) end)
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
        Logger.flush()
      end)

    assert log =~ "QUERY ERROR"
    assert log =~ "not-a-share"
    refute log =~ secret
  end
end
