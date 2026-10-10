defmodule DawarichWeb.ShareManagementEndpointTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.{Repo, Sharing}
  alias Dawarich.Test.{FrameSeeds, RailsUser, RailsFormRequests}
  @endpoint DawarichWeb.Endpoint
  @now ~U[2026-10-03 10:00:00Z]
  setup do
    actor = FrameSeeds.seed_management!("hub_active_shared_en")
    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  defp open(actor, path),
    do: elem(live(RailsUser.signed_in(actor.id) |> RailsUser.connecting_as(actor.id), path), 1)

  defp confirm(view, action) do
    render_hook(view, "sharing_prepare", %{"action" => Atom.to_string(action)})
    render_hook(view, "sharing_confirm", %{})
  end

  defp change(actor, type, action, attrs) do
    resource =
      if type == :trip,
        do: %{type: type, id: 99101, owner_id: actor.id},
        else: %{type: type, owner_id: actor.id}

    Sharing.change(Dawarich.Accounts.Scope.for_user(actor, "en"), resource, action, attrs,
      now: @now
    )
  end

  @tag mutation: "target"
  test "native live and trip CRUD retain notices rotation and validation", ctx do
    for base <- ["/share_links/live", "/trips/99101/share_link"] do
      view = open(ctx.actor, base <> "/new")

      render_submit(view, "sharing_create", %{
        "shared_link" => %{"magic_phrase" => "", "expires_at" => ""}
      })

      assert has_element?(view, "[role=alert]", "Share link created.")

      for {action, notice} <- [
            {:regenerate, "URL regenerated."},
            {:regenerate_phrase, "Magic phrase regenerated."},
            {:revoke, "Share link revoked."}
          ] do
        prior = ids(ctx.actor.id)
        confirm(view, action)
        assert has_element?(view, "[role=alert]", notice)
        if action == :regenerate, do: refute(ids(ctx.actor.id) == prior)
      end

      render_submit(view, "sharing_create", %{
        "shared_link" => %{"magic_phrase" => "", "expires_at" => ""}
      })

      prior = ids(ctx.actor.id)
      confirm(view, :destroy)
      assert length(ids(ctx.actor.id)) == length(prior) - 1
      render_submit(view, "sharing_create", %{"shared_link" => %{"expires_at" => "2020-01-01"}})
      assert has_element?(view, "[role=alert]")
      assert length(ids(ctx.actor.id)) == length(prior) - 1
      refute has_element?(view, "turbo-frame, [data-controller]")
    end
  end

  @tag mutation: "csrf"
  test "native retired sharing envelopes refuse CSRF origin type and overrides before effects",
       ctx do
    upstream = RailsFormRequests.upstream!()
    original = ids(ctx.actor.id)

    for {body, headers} <- [
          {"authenticity_token=wrong&shared_link%5Bname%5D=untouched", []},
          {"shared_link[name]=untouched", [{"origin", "https://foreign.test"}]},
          {~s({"shared_link":{"name":"untouched"}}), [{"content-type", "application/json"}]},
          {~s({"shared_link":{"name":"untouched"}}), [{"content-type", "application/xml"}]},
          {"_method=put", []}
        ] do
      conn =
        build_conn()
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
        |> put_req_header("content-type", "application/x-www-form-urlencoded")

      conn =
        Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

      assert post(conn, "/share_links/live", body).status == 404
      assert ids(ctx.actor.id) == original
      assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    end
  end

  @tag mutation: "key"
  test "native compatibility keys cannot hand back sharing pages or events", ctx do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)
    upstream = RailsFormRequests.upstream!()

    for {key, path} <- [
          {"share_links", "/share_links/live/new"},
          {"trip_shares", "/trips/99101/share_link/new"},
          {"trips", "/trips/99101/share_link/new"}
        ] do
      Application.put_env(:dawarich, :rails_routes, [key])
      view = open(ctx.actor, path)
      render_submit(view, "sharing_create", %{"shared_link" => %{}})
      assert has_element?(view, "#native-sharing")
      assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
    end
  end

  @tag mutation: "effect-fence"
  test "native committed sharing remains terminal when response rendering fails", ctx do
    view = open(ctx.actor, "/share_links/live/new")
    socket = :sys.get_state(view.pid).socket

    socket = %{
      socket
      | assigns:
          Map.delete(socket.assigns, :flash)
          |> Map.put(:confirmation, %{resource: socket.assigns.resource, action: :revoke})
    }

    assert_raise KeyError, fn ->
      DawarichWeb.SharingLive.Index.handle_event("sharing_confirm", %{}, socket)
    end

    before = ids(ctx.actor.id)

    socket = %{socket | assigns: Map.put(socket.assigns, :confirmation, nil)}

    assert {:noreply, _} =
             DawarichWeb.SharingLive.Index.handle_event("sharing_confirm", %{}, socket)

    assert ids(ctx.actor.id) == before
  end

  @tag mutation: "replacement"
  test "native invalid live replacement rolls back and preserves compatibility broadcasts", ctx do
    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)
    before = Repo.query!("SELECT id::text,revoked_at FROM shared_links ORDER BY id").rows

    assert {:error, %{errors: [_ | _]}} =
             change(ctx.actor, :live, :create, %{
               "shared_link" => %{"magic_phrase" => String.duplicate("a", 256)}
             })

    assert Repo.query!("SELECT id::text,revoked_at FROM shared_links ORDER BY id").rows == before
    assert commands() == []

    assert Repo.query!("SELECT payload FROM phoenix.cable_events ORDER BY seq").rows
           |> Enum.map(fn [payload] -> Jason.decode!(payload) end) == [
             %{"revoked" => true},
             %{"revoked" => true}
           ]
  end

  @tag mutation: "nested"
  test "native checkbox last value survives while scalar map collisions refuse without effects",
       ctx do
    assert {:ok, params} =
             DawarichWeb.Api.SourceParams.decode(
               "shared_link[settings][show_stats]=0&shared_link[settings][show_stats]=1"
             )

    assert {:ok, _} = change(ctx.actor, :trip, :create, params)

    assert [[true]] =
             Repo.query!(
               "SELECT (settings->>'show_stats')::boolean FROM shared_links WHERE user_id=$1 AND resource_type=0 AND revoked_at IS NULL",
               [ctx.actor.id]
             ).rows

    before = ids(ctx.actor.id)

    for body <- [
          "shared_link=scalar&shared_link[name]=nested",
          "shared_link[name]=nested&shared_link=scalar",
          "shared_link[settings]=scalar&shared_link[settings][show_stats]=1"
        ] do
      case DawarichWeb.Api.SourceParams.decode(body) do
        {:error, _} -> :ok
        {:ok, params} -> assert {:error, _} = change(ctx.actor, :live, :create, params)
      end

      assert ids(ctx.actor.id) == before
    end
  end

  @tag mutation: "broadcast-order"
  test "native replacement preserves primary key order for old live broadcasts", ctx do
    saved = Application.get_env(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, saved) end)

    fixture =
      "test/fixtures/share_management/hub_active_shared_en.json"
      |> File.read!()
      |> Jason.decode!()

    old =
      Enum.filter(
        fixture["before"],
        &(&1["user_id"] == ctx.actor.id and &1["resource_type"] == 3 and &1["expires_at"] == nil and
            &1["revoked_at"] == nil)
      )

    Repo.query!("DELETE FROM shared_links WHERE user_id = $1 AND resource_type = 3", [
      ctx.actor.id
    ])

    for row <- Enum.reverse(old), do: Dawarich.Test.ApiGolden.insert!("shared_links", row)
    assert {:ok, _} = change(ctx.actor, :live, :create, %{"shared_link" => %{}})

    assert Repo.query!("SELECT channel FROM phoenix.cable_events ORDER BY seq").rows
           |> Enum.map(fn [stream] ->
             stream
             |> String.replace_prefix("shared_location:", "")
             |> Base.url_decode64!(padding: false)
             |> String.split("/")
             |> List.last()
           end) ==
             Enum.map(old, & &1["id"])
  end

  defp ids(user),
    do: Repo.query!("SELECT id::text FROM shared_links WHERE user_id=$1 ORDER BY id", [user]).rows
end
