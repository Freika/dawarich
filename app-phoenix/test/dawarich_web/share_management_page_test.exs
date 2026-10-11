defmodule DawarichWeb.ShareManagementPageTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint
  setup do
    actor = FrameSeeds.seed_management!("hub_active_shared_en")
    %{actor: actor}
  end

  defp connection(id), do: RailsUser.signed_in(id) |> RailsUser.connecting_as(id)
  defp create_attrs, do: %{"shared_link" => %{"magic_phrase" => "", "expires_at" => ""}}

  test "native sharing document variants preserve resource forms and validation in place", c do
    for path <- ~w(/share_links/hub /share_links/live/new /trips/99101/share_link/new) do
      Repo.query!("DELETE FROM shared_links WHERE user_id=$1", [c.actor.id], log: false)
      {:ok, view, _} = live(connection(c.actor.id), path)
      assert has_element?(view, "#native-sharing")
      refute has_element?(view, "[data-controller], turbo-frame")

      render_submit(view, "sharing_create", %{
        "shared_link" => %{
          "name" => String.duplicate("long", 70),
          "magic_phrase" => "",
          "expires_at" => ""
        }
      })

      assert has_element?(view, "[role=alert]")

      assert Repo.query!("SELECT count(*) FROM shared_links WHERE user_id=$1", [c.actor.id],
               log: false
             ).rows == [[0]]

      render_submit(view, "sharing_create", create_attrs())

      assert Repo.query!("SELECT count(*) FROM shared_links WHERE user_id=$1", [c.actor.id],
               log: false
             ).rows == [[1]]
    end
  end

  test "native hub normalizes an unknown tab to a usable live form", c do
    Repo.query!("DELETE FROM shared_links WHERE user_id=$1", [c.actor.id], log: false)
    {:ok, view, _} = live(connection(c.actor.id), "/share_links/hub?tab=unknown")
    assert :sys.get_state(view.pid).socket.assigns.tab == "live"
    assert has_element?(view, "form[phx-submit=sharing_create]")
    render_submit(view, "sharing_create", create_attrs())

    assert Repo.query!("SELECT resource_type FROM shared_links WHERE user_id=$1", [c.actor.id],
             log: false
           ).rows == [[3]]
  end

  test "native hub retains ordered sharing settings tabs and ordinary studio entrypoints", c do
    {:ok, view, _} = live(connection(c.actor.id), "/share_links/hub?tab=shared")

    for tab <- ~w(live timeline make shared),
        do: assert(has_element?(view, "[data-testid=hub-tab-#{tab}]"))

    shares = :sys.get_state(view.pid).socket.assigns.page.shares
    assert length(shares) == 5

    assert Enum.map(shares, & &1.created_at) ==
             Enum.sort(Enum.map(shares, & &1.created_at), {:desc, NaiveDateTime})

    assert Enum.map(shares, & &1.type) |> Enum.sort() == ~w(live live timeline track trip)
    render_patch(view, "/share_links/hub?tab=make")
    assert has_element?(view, "a[data-testid=hub-make-video][href='/map/v2?studio=video']")
    assert has_element?(view, "a[data-testid=hub-make-poster][href='/map/v2?studio=poster']")
    Repo.query!("DELETE FROM shared_links WHERE user_id=$1", [c.actor.id], log: false)
    render_patch(view, "/share_links/hub?tab=shared")
    assert :sys.get_state(view.pid).socket.assigns.tab == "live"
    assert has_element?(view, "form[phx-submit=sharing_create]")
    render_submit(view, "sharing_create", create_attrs())

    assert Repo.query!("SELECT resource_type FROM shared_links WHERE user_id=$1", [c.actor.id],
             log: false
           ).rows == [[3]]
  end

  test "manager frame hints do not change owned admission and foreign resources return safely",
       c do
    for path <- ~w(/share_links/live/new /trips/99101/share_link/new) do
      for frame <- ~w(share-link-modal wrong-frame) do
        html =
          connection(c.actor.id)
          |> put_req_header("turbo-frame", frame)
          |> get(path)
          |> html_response(200)

        assert html =~ "/native/app"
        refute html =~ "<turbo-frame"
      end
    end

    for path <-
          ~w(/trips/99102/share_link/new /trips/99999/share_link/new /tracks/no/share_link/new) do
      assert {:error, {:redirect, %{to: "/map/v2"}}} = live(connection(c.actor.id), path)
    end

    assert build_conn() |> get("/share_links/live/new") |> redirected_to() ==
             "http://www.example.com/users/sign_in"
  end

  test "trip route compatibility hints leave both native manager and trip host owned", c do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)

    for key <- ~w(trip_shares trips) do
      Application.put_env(:dawarich, :rails_routes, [key])
      {:ok, view, _} = live(connection(c.actor.id), "/trips/99101/share_link/new")

      assert :sys.get_state(view.pid).socket.assigns.resource == %{
               type: :trip,
               id: 99101,
               owner_id: c.actor.id
             }

      assert has_element?(view, "a[href='/trips/99101']")
    end
  end

  test "share compatibility hints preserve native manager commands and the native public map owner",
       c do
    saved = Application.get_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_routes, ["share_links"])
    on_exit(fn -> Application.put_env(:dawarich, :rails_routes, saved) end)
    {:ok, view, _} = live(connection(c.actor.id), "/share_links/hub")
    render_submit(view, "sharing_create", create_attrs())
    assert has_element?(view, "#native-sharing")

    info =
      Phoenix.Router.route_info(
        DawarichWeb.Router,
        "GET",
        "/s/a9f10000-0000-4000-8000-000000000002",
        "www.example.com"
      )

    assert info.plug == Phoenix.LiveView.Plug

    assert {DawarichWeb.PublicMapLive, :show, _, %{name: :native_m6_public}} =
             info.phoenix_live_view
  end
end
