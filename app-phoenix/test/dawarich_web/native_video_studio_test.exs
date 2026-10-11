defmodule DawarichWeb.NativeVideoStudioTest do
  use Dawarich.DataCase, async: true

  import Phoenix.LiveViewTest

  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.NativeVideoStudio

  @endpoint DawarichWeb.Endpoint
  @bytes String.duplicate("v", 4096)
  @checksum Base.encode64(:crypto.hash(:md5, @bytes))
  @themes [%{key: "terracotta", name: "Terracotta"}, %{key: "noir", name: "Noir"}]

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, %{"user_id" => id} = session, socket) do
      {:ok,
       assign(socket,
         scope: Maps.principal(Accounts.get(id), "de"),
         fixed: session["fixed"],
         events: []
       )}
    end

    def handle_info({DawarichWeb.VideoStudioLiveComponent, event}, socket),
      do: {:noreply, update(socket, :events, &[event | &1])}

    def render(assigns) do
      ~H"""
      <p id="host-events">{inspect(@events)}</p>
      <.live_component
        module={DawarichWeb.VideoStudioLiveComponent}
        id="video-studio-owner"
        scope={@scope}
        locale="de"
        base_url="http://www.example.com"
        themes={[%{key: "terracotta", name: "Terracotta"}]}
        fixed_range_label={@fixed}
      />
      """
    end
  end

  setup do
    Ownership.put!(Repo, "cron:route_videos_purge_job", :oban)
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "video-studio-#{id}@dawarich.test",
      api_key: "synthetic-video-key"
    })

    %{id: id}
  end

  defp render_studio(attrs \\ %{}) do
    html =
      render_component(
        &NativeVideoStudio.video_studio/1,
        Map.merge(%{themes: @themes, locale: "de", fixed_range_label: nil}, attrs)
      )

    {html, LazyHTML.from_fragment(html)}
  end

  defp attribute(doc, selector, name),
    do: doc |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  defp live!(id, session \\ %{}) do
    {:ok, view, html} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host, session: Map.put(session, "user_id", id))

    {view, html}
  end

  defp hook(view, event, payload),
    do: view |> element("#native-video-studio") |> render_hook(event, payload)

  defp target(view) do
    hook(view, "video:upload_target", %{
      "byte_size" => 4096,
      "checksum" => @checksum,
      "filename" => "Leipzig.mp4"
    })

    assert_reply(view, %{ok: true, reference: signed, url: url})
    {signed, url}
  end

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

  test "native video studio is a keyed hook root whose ignored islands hold only browser-owned state" do
    {html, doc} = render_studio()

    assert attribute(doc, "#native-video-studio", "phx-hook") == ["VideoStudio"]

    assert attribute(doc, "[phx-update=ignore]", "id") ==
             ~w(native-video-dates native-video-range native-video-stage native-video-controls native-video-actions)

    assert attribute(doc, "dialog[data-video-dialog]", "phx-mounted") |> hd() =~ "ignore_attrs"
    assert count(doc, "#native-video-stage [data-video-preview]") == 1
    assert count(doc, "#native-video-stage canvas[data-video-overlay]") == 1
    assert count(doc, "#native-video-actions [data-video-render][disabled]") == 1
    assert count(doc, "[data-video-theme]") == 2
    assert count(doc, "[data-video-format]") == 3
    assert count(doc, "[data-video-setting]") == 11
    refute html =~ ~r/data-controller|data-action|video-studio#|turbo|stimulus|api_key/i

    {_html, trip} = render_studio(%{fixed_range_label: "1. Okt. 2026 – 2. Okt. 2026"})
    assert count(trip, "[data-video-start]") == 0
    assert trip |> LazyHTML.query("[data-video-range-label]") |> LazyHTML.text() =~ "1. Okt. 2026"
  end

  test "video studio config carries localized strings and digested font URLs only" do
    {_html, doc} = render_studio()
    [json] = attribute(doc, "#native-video-studio", "data-video-config")
    config = Jason.decode!(json)

    assert Map.keys(config) |> Enum.sort() == ["fonts", "strings"]
    assert config["fonts"]["inter-400"] =~ "inter-400"
    assert config["fonts"]["jetbrains-mono-700"] =~ "jetbrains-mono-700"
    assert config["strings"]["open_failed"] =~ "%{error}"
    assert config["strings"]["hud.travelled_over"] =~ "%{days}"
    assert config["strings"]["start_before_end"] != "start_before_end"
    refute config["strings"]["hud.distance"] == "DISTANCE"
  end

  test "upload target replies once to the hook and never renders the reference", %{id: id} do
    {view, html} = live!(id)
    refute html =~ "synthetic-video-key"
    {signed, url} = target(view)
    assert url =~ "/rails/active_storage/disk/"
    refute render(view) =~ signed

    hook(view, "video:upload_target", %{
      "byte_size" => 300 * 1024 * 1024,
      "checksum" => @checksum,
      "filename" => "big.mp4"
    })

    assert_reply(view, %{ok: false, error: error})
    assert error == DawarichWeb.Translate.t("de", "controllers.route_videos.rejected_file", %{})
  end

  test "saving a fresh upload creates one video and notifies the host", %{id: id} do
    {view, _html} = live!(id)
    {signed, _url} = target(view)
    store(signed)

    hook(view, "video:save", %{
      "reference" => signed,
      "name" => "Leipzig",
      "settings" => %{"format" => "square", "watermark" => "false", "source" => "map"}
    })

    assert_reply(view, %{ok: true, id: video})
    assert rows("SELECT user_id,name FROM route_videos WHERE id=$1", [video]) == [[id, "Leipzig"]]
    assert render(view) =~ "{:saved, #{video}, []}"

    hook(view, "video:save", %{"reference" => signed, "name" => "again", "settings" => %{}})
    assert_reply(view, %{ok: false})
    assert rows("SELECT count(*) FROM route_videos WHERE user_id=$1", [id]) == [[1]]
  end

  test "a discarded or revoked upload never becomes a gallery row", %{id: id} do
    {view, _html} = live!(id)
    {signed, _url} = target(view)
    hook(view, "video:discard", %{"reference" => signed})
    assert_reply(view, %{ok: true})
    hook(view, "video:save", %{"reference" => signed, "name" => "x", "settings" => %{}})
    assert_reply(view, %{ok: false})

    {other, _url} = target(view)
    rows("UPDATE users SET encrypted_password=$2 WHERE id=$1", [id, String.duplicate("r", 60)])
    hook(view, "video:save", %{"reference" => other, "name" => "x", "settings" => %{}})
    assert_reply(view, %{ok: false})

    hook(view, "video:upload_target", %{
      "byte_size" => 1,
      "checksum" => @checksum,
      "filename" => "a.mp4"
    })

    assert_reply(view, %{ok: false})
    assert rows("SELECT count(*) FROM route_videos WHERE user_id=$1", [id]) == [[0]]

    assert rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [other]) == [
             ["pending"]
           ]
  end
end
