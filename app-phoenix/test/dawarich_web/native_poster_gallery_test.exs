defmodule DawarichWeb.NativePosterGalleryTest.Host do
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.MapLiveAuth, :default}

  alias DawarichWeb.NativePosterGallery

  def mount(_params, _session, socket), do: {:ok, NativePosterGallery.mount(socket)}

  def render(assigns) do
    ~H"""
    <DawarichWeb.NativePosterCard.poster_gallery posters={@posters} locale="en" />
    """
  end

  def handle_event(event, params, socket),
    do: NativePosterGallery.handle_event(event, params, socket)

  def handle_info(message, socket) do
    case NativePosterGallery.handle_info(message, socket) do
      :unhandled -> {:noreply, socket}
      handled -> handled
    end
  end
end

defmodule DawarichWeb.NativePosterGalleryTest.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :probe do
    plug DawarichWeb.RailsAuth
    plug :fetch_live_flash
  end

  scope "/" do
    pipe_through :probe

    live_session :native_poster_gallery_probe,
      session: {DawarichWeb.MapLiveAuth, :live_session, []} do
      live "/", DawarichWeb.NativePosterGalleryTest.Host
    end
  end
end

defmodule DawarichWeb.NativePosterGalleryTest do
  use Dawarich.DataCase, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Posters.Persistence
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.NativePosterGallery

  @endpoint DawarichWeb.Endpoint

  @recipe %{
    "name" => "Gallery",
    "title" => "Berlin",
    "theme" => "noir",
    "lat" => 52.52,
    "lon" => 13.405,
    "distance" => 6000,
    "start_at" => "2026-10-01T00:00",
    "end_at" => "2026-10-02T00:00",
    "source" => "tracks",
    "route_opacity" => "100",
    "route_width" => "100"
  }

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    RailsUser.insert!(%{id: 96_401, email: "gallery@dawarich.test", api_key: "gallery-key"})
    RailsUser.insert!(%{id: 96_402, email: "other@dawarich.test", api_key: "other-key"})
    %{id: 96_401, other: 96_402}
  end

  defp probe(id) do
    RailsUser.signed_in(id)
    |> RailsUser.connecting_as(id)
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_private(:phoenix_endpoint, @endpoint)
    |> Plug.Conn.fetch_query_params()
    |> DawarichWeb.NativePosterGalleryTest.Router.call([])
    |> live()
  end

  defp progress(user_id, poster_id), do: {:poster_changed, user_id, poster_id}

  defp cards(html), do: html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-poster-card]")

  defp phase(id, phase) do
    Repo.query!(
      "UPDATE posters SET settings = settings || jsonb_build_object('progress_phase', $2::text) WHERE id = $1",
      [id, phase]
    )
  end

  test "native poster gallery consumes its committed domain progress producer", %{id: id} do
    {:ok, poster} = Persistence.create(@recipe, %{id: id}, "en")
    {:ok, view, _} = probe(id)
    phase(poster, "saving")

    args = %{
      "poster_id" => poster,
      "user_id" => id,
      "locale" => "en",
      "event_id" => Ecto.UUID.generate()
    }

    Phoenix.PubSub.subscribe(Dawarich.PubSub, "posters:user:#{id}")

    assert :ok =
             Dawarich.Posters.ProgressWorker.run(Repo, args, publish: fn _, _, _, _, _ -> :ok end)

    assert_receive {:poster_changed, ^id, ^poster}
    assert render(view) =~ "Saving"
  end

  test "queued create returns one card and reconnect reloads current status", %{id: id} do
    {:ok, view, _} = probe(id)
    render_hook(view, "poster:save", @recipe)
    assert_reply(view, %{status: "queued"})

    assert [card] = view |> render() |> cards() |> Enum.to_list()
    assert LazyHTML.text(card) =~ "Gallery"
    assert [[poster]] = rows("SELECT id FROM posters WHERE user_id = $1", [id])
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]

    state = inspect(:sys.get_state(view.pid), limit: :infinity)
    refute state =~ "52.52"
    refute state =~ "gallery-key"

    phase(poster, "drawing_map")
    {:ok, reconnected, _} = probe(id)
    assert render(reconnected) =~ "Drawing the map"
  end

  test "gallery progress after revoke is dropped", %{id: id} do
    {:ok, poster} = Persistence.create(@recipe, %{id: id}, "en")
    scope = Maps.principal(Accounts.get(id), "en")
    {:ok, [card]} = Dawarich.Posters.gallery(scope)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, current_scope: scope, posters: [card], flash: %{}}
    }

    phase(poster, "drawing_map")
    {:noreply, updated} = NativePosterGallery.handle_info(progress(id, poster), socket)
    assert [%{settings: %{"progress_phase" => "drawing_map"}}] = updated.assigns.posters

    {:ok, view, _} = probe(id)

    Repo.query!("UPDATE users SET encrypted_password = $1 WHERE id = $2", [
      String.duplicate("changed", 10),
      id
    ])

    phase(poster, "saving")
    {:noreply, dropped} = NativePosterGallery.handle_info(progress(id, poster), socket)
    assert dropped.assigns.posters == [card]

    send(view.pid, progress(id, poster))
    assert_redirect(view, "/users/sign_in")
  end

  test "own poster progress replaces its card and foreign or unrelated events change nothing",
       %{id: id, other: other} do
    {:ok, own} = Persistence.create(@recipe, %{id: id}, "en")
    {:ok, foreign} = Persistence.create(@recipe, %{id: other}, "en")
    {:ok, view, _} = probe(id)

    phase(own, "saving")
    send(view.pid, progress(other, own))
    send(view.pid, progress(id, foreign))
    send(view.pid, :unrelated)
    refute render(view) =~ "Saving"
    send(view.pid, progress(id, own))
    assert render(view) =~ "Saving"

    render_hook(view, "poster:delete", %{"id" => Integer.to_string(foreign)})
    render_hook(view, "poster:delete", %{})
    assert rows("SELECT count(*) FROM posters WHERE id = $1", [foreign]) == [[1]]
    assert view |> render() |> cards() |> Enum.count() == 1

    render_hook(view, "poster:delete", %{"id" => Integer.to_string(own)})
    assert view |> render() |> cards() |> Enum.count() == 0
    assert rows("SELECT count(*) FROM posters WHERE id = $1", [own]) == [[0]]
  end

  test "native poster cards delete through a confirmed LiveView event without Turbo" do
    html =
      render_component(&DawarichWeb.NativePosterCard.poster_card/1,
        poster: %{
          id: 7,
          name: "Gallery",
          status: 3,
          settings: %{"error" => "No location data"},
          files: %{"image" => nil, "print_pdf" => nil}
        },
        locale: "de"
      )

    doc = LazyHTML.from_fragment(html)

    assert doc
           |> LazyHTML.query("button[phx-click='poster:delete']")
           |> LazyHTML.attribute("phx-value-id") == ["7"]

    assert doc |> LazyHTML.query("[data-confirm]") |> Enum.count() == 1
    assert html =~ "No location data"
    refute html =~ ~r/turbo|data-controller|data-action/
  end
end
