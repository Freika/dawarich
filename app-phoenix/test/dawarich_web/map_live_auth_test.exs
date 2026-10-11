defmodule DawarichWeb.MapLiveAuthTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps, Repo}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.MapLiveAuth
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    row =
      RailsUser.insert!(%{
        id: 96002,
        email: "map-hook@dawarich.test",
        api_key: "synthetic-hook-key"
      })

    scope = Maps.principal(Accounts.get(row.id), "en")

    session = %{
      "rails_user_id" => row.id,
      "map_identity" => scope.user.session_version,
      "locale" => "en"
    }

    %{id: row.id, session: session}
  end

  defp probe(id) do
    conn =
      RailsUser.signed_in(id)
      |> RailsUser.connecting_as(id)
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
      |> Plug.Conn.fetch_query_params()
      |> Dawarich.Test.NativeMapProbeRouter.call([])

    live(conn)
  end

  test "native map callbacks retain immutable identity and secret-free state", %{id: id} do
    {:ok, view, _} = probe(id)
    render_hook(view, "command", %{})
    assert render(view) =~ ">1</output>"
    state = inspect(:sys.get_state(view.pid), limit: :infinity)
    refute state =~ "synthetic-hook-key"
    refute state =~ Accounts.get(id).encrypted_password

    Repo.query!("UPDATE users SET encrypted_password = $1 WHERE id = $2", [
      String.duplicate("changed", 10),
      id
    ])

    render_hook(view, "command", %{})
    assert_redirect(view, "/users/sign_in")
  end

  test "native map queued result is refused after actor revocation", %{id: id} do
    {:ok, view, _} = probe(id)
    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = $1", [id])
    send(view.pid, :late_result)
    assert_redirect(view, "/users/sign_in")
  end

  test "native map params reject a revoked session before loading a new range", %{id: id} do
    {:ok, view, _} = probe(id)
    Repo.query!("UPDATE users SET deleted_at = now() WHERE id = $1", [id])
    render_patch(view, "/?probe=range")
    assert_redirect(view, "/users/sign_in")
  end

  test "native map async delivery checks the original session after refresh", %{id: id} do
    Application.put_env(:dawarich, :native_map_probe_owner, self())
    on_exit(fn -> Application.delete_env(:dawarich, :native_map_probe_owner) end)
    {:ok, view, _} = probe(id)
    render_hook(view, "command", %{})
    render_hook(view, "begin", %{})
    assert_receive {:map_probe_task, task}

    Repo.query!("UPDATE users SET encrypted_password = $1 WHERE id = $2", [
      String.duplicate("changed", 10),
      id
    ])

    send(task, :release)
    assert_redirect(view, "/users/sign_in")
  end

  test "map resource refusal clears page without redirecting to its own URL" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        page: %{place: %{id: 1}},
        current_user: nil,
        current_scope: nil
      }
    }

    socket = MapLiveAuth.refuse(socket, :not_found)
    assert socket.assigns.page == nil
    assert socket.assigns.map_error == :not_found
    assert socket.redirected == nil
  end
end
