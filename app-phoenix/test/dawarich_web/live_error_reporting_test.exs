defmodule DawarichWeb.LiveErrorReportingTest do
  use Dawarich.ErrorReportingCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint DawarichWeb.Endpoint

  defmodule SharedLive do
    use DawarichWeb, :live_view

    def mount(_params, session, socket) do
      if connected?(socket) and session["crash"] == "mount",
        do: raise("victim@example.invalid private-cookie 654321")

      {:ok, assign(socket, :personal, session["personal"])}
    end

    def handle_event("crash", params, _socket), do: raise(inspect(params))
    def render(assigns), do: ~H"<button phx-click=\"crash\">Crash</button>"
  end

  defmodule DirectLive do
    use Phoenix.LiveView
    def mount(params, session, socket), do: SharedLive.mount(params, session, socket)
    def handle_event(event, params, socket), do: SharedLive.handle_event(event, params, socket)
    def render(assigns), do: SharedLive.render(assigns)
  end

  test "connected LiveView mount and event crashes report once without socket or session PII" do
    Process.flag(:trap_exit, true)

    for module <- [SharedLive, DirectLive], stage <- ["mount", "event"] do
      conn = build_conn()
      session = %{"crash" => stage, "personal" => "Synthetic Person private-cookie"}

      if stage == "mount" do
        catch_exit(live_isolated(conn, module, session: session))
      else
        {:ok, view, _} = live_isolated(conn, module, session: session)

        catch_exit(
          render_click(view, "crash", %{"otp" => "654321", "email" => "victim@example.invalid"})
        )
      end

      {_item, payload} = envelope()
      assert hd(payload["exception"])["type"] == "RuntimeError"
      assert hd(payload["exception"])["stacktrace"]["frames"] != []
      assert payload["tags"]["surface"] == "live_view"
      assert_private(payload)
      refute_receive {:envelope, _, _}
    end
  end
end
