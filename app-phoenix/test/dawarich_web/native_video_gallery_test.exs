defmodule DawarichWeb.NativeVideoGalleryTest do
  use Dawarich.DataCase, async: false

  import Phoenix.LiveViewTest

  alias Dawarich.{Accounts, MapGallery, Maps, RailsMessages, RouteVideos}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser

  @endpoint DawarichWeb.Endpoint
  @bytes String.duplicate("v", 4096)
  @checksum Base.encode64(:crypto.hash(:md5, @bytes))

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, %{"user_id" => id}, socket),
      do: {:ok, assign(socket, scope: Maps.principal(Accounts.get(id), "en"))}

    def handle_info({DawarichWeb.VideoStudioLiveComponent, _event}, socket),
      do: {:noreply, socket}

    def render(assigns) do
      ~H"""
      <.live_component
        module={DawarichWeb.VideoStudioLiveComponent}
        id="video-studio-owner"
        scope={@scope}
        locale="en"
        base_url="http://www.example.com"
        themes={[%{key: "terracotta", name: "Terracotta"}]}
      />
      """
    end
  end

  setup do
    Ownership.put!(Repo, "cron:route_videos_purge_job", :oban)
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "video-gallery-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{id: id, scope: Maps.principal(Accounts.get(id), "en")}
  end

  defp live!(id) do
    {:ok, view, html} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: %{"user_id" => id})

    {view, html}
  end

  defp save!(scope, name) do
    {:ok, blob} =
      RouteVideos.reserve_upload(
        scope,
        %{
          "filename" => "#{name}.mp4",
          "content_type" => "video/mp4",
          "byte_size" => 4096,
          "checksum" => @checksum
        },
        []
      )

    {:ok, %{id: video}} =
      RouteVideos.create_video(
        scope,
        %{
          "signed_id" => RailsMessages.blob_id(blob.id),
          "name" => name,
          "settings" => %{"format" => "square", "source" => "map"}
        },
        []
      )

    video
  end

  defp card(id), do: "#native-route-video-#{id}"
  defp doc(html), do: LazyHTML.from_fragment(html)

  defp attribute(html, selector, name),
    do: html |> doc() |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp count(html, selector), do: html |> doc() |> LazyHTML.query(selector) |> Enum.count()

  defp revoke!(id),
    do:
      rows("UPDATE users SET encrypted_password=$2 WHERE id=$1", [id, String.duplicate("r", 60)])

  defp store(reference) do
    [[key]] =
      rows(
        "SELECT b.key FROM active_storage_blobs b JOIN phoenix.native_uploads u ON u.blob_id=b.id WHERE u.reference=$1",
        [reference]
      )

    config = Dawarich.Imports.StorageContext.storage()
    path = Dawarich.Storage.disk_path(config.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, @bytes)
    on_exit(fn -> File.rm(path) end)
  end

  test "saved video appears as a native card with its MP4 download", %{id: id} do
    {view, html} = live!(id)
    assert count(html, "#native-video-gallery-list") == 1

    view
    |> element("#native-video-studio")
    |> render_hook("video:upload_target", %{
      "byte_size" => 4096,
      "checksum" => @checksum,
      "filename" => "Leipzig.mp4"
    })

    assert_reply(view, %{ok: true, reference: signed})
    store(signed)

    view
    |> element("#native-video-studio")
    |> render_hook("video:save", %{"reference" => signed, "name" => "Leipzig", "settings" => %{}})

    assert_reply(view, %{ok: true, id: video})
    html = render(view)
    file = MapGallery.route_video(id, video, "Europe/Berlin").files["file"]

    assert html |> doc() |> LazyHTML.query("#{card(video)} h4") |> LazyHTML.text() == "Leipzig"

    assert attribute(html, "#{card(video)} a[data-video-download]", "href") ==
             [MapGallery.blob_path(file, "attachment")]

    assert count(html, "#{card(video)} [data-video-restore]") == 0
    refute html =~ ~r/data-turbo|data-action|video-studio#|route_video_#{video}"/
  end

  test "video delete remains deleted after reconnect and reload", %{id: id, scope: scope} do
    video = save!(scope, "Leipzig")
    {view, html} = live!(id)

    assert attribute(html, "#{card(video)} [data-video-delete]", "data-confirm") ==
             ["Delete this video?"]

    view |> element("#{card(video)} [data-video-delete]") |> render_click()

    assert count(render(view), card(video)) == 0
    assert rows("SELECT count(*) FROM route_videos WHERE user_id=$1", [id]) == [[0]]

    {_view, html} = live!(id)
    assert count(html, card(video)) == 0
  end

  test "revoked actor receives no gallery update", %{id: id, scope: scope} do
    first = save!(scope, "First")
    {view, html} = live!(id)
    assert count(html, card(first)) == 1
    second = save!(scope, "Second")
    revoke!(id)

    view |> element("#{card(first)} [data-video-delete]") |> render_click()

    html = render(view)
    assert count(html, card(second)) == 0
    refute html =~ "Second"
    assert rows("SELECT count(*) FROM route_videos WHERE user_id=$1", [id]) == [[2]]
  end

  test "an evicted video keeps its settings to re-render and offers no download", %{
    id: id,
    scope: scope
  } do
    video = save!(scope, "Evicted")

    rows(
      "UPDATE route_videos SET status=1, expired_at=$2 WHERE id=$1",
      [video, ~N[2026-10-01 10:00:00]]
    )

    {_view, html} = live!(id)

    assert count(html, "#{card(video)} [data-video-download]") == 0
    assert html |> doc() |> LazyHTML.query(card(video)) |> LazyHTML.text() =~ "October 01, 2026"
    [click] = attribute(html, "#{card(video)} [data-video-restore]", "phx-click")
    assert click =~ "dawarich:video-studio-open"
    assert click =~ "#native-video-studio"
    assert click =~ ~s(\\"format\\":\\"square\\")
  end

  test "another account's video never enters the gallery and cannot be deleted", %{
    id: id,
    scope: scope
  } do
    other = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: other,
      email: "video-gallery-#{other}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    foreign = save!(Maps.principal(Accounts.get(other), "en"), "Foreign")
    mine = save!(scope, "Mine")
    {view, html} = live!(id)
    assert count(html, card(mine)) == 1
    assert count(html, card(foreign)) == 0

    view
    |> element("#native-video-studio")
    |> render_hook("video:delete", %{"id" => to_string(foreign)})

    html = render(view)
    assert count(html, card(mine)) == 1
    refute html =~ "Foreign"
    assert rows("SELECT user_id FROM route_videos WHERE id=$1", [foreign]) == [[other]]

    assert rows(
             "SELECT count(*) FROM active_storage_attachments WHERE record_type='RouteVideo' AND record_id=$1",
             [foreign]
           ) == [[1]]
  end

  test "an unknown or nonstring zone refuses the gallery with a typed error", %{
    id: id,
    scope: scope
  } do
    video = save!(scope, "Zoned")
    assert {:ok, [%{id: ^video}]} = RouteVideos.gallery(scope, [])

    for zone <- ["Mars/Unknown", %{}] do
      rows("UPDATE users SET settings=$2 WHERE id=$1", [id, %{"timezone" => zone}])
      assert RouteVideos.gallery(scope, []) == {:error, :invalid_zone}
    end
  end
end
