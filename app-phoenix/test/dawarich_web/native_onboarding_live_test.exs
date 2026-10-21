defmodule DawarichWeb.NativeOnboardingLiveTest do
  use Dawarich.DataCase, async: true
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Maps}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  defmodule Host do
    use Phoenix.LiveView

    def mount(_params, %{"user_id" => id, "auto" => auto}, socket) do
      user = Accounts.get(id)
      navbar = Dawarich.Navbar.load(user, now: DateTime.utc_now(), self_hosted: true)

      {:ok,
       assign(socket,
         scope: Maps.principal(user, "en"),
         navbar: navbar,
         auto: auto
       )}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={DawarichWeb.OnboardingLiveComponent}
        id="onboarding"
        scope={@scope}
        navbar={@navbar}
        locale="en"
        base_url="http://localhost"
        rails_csrf_token="token"
        auto_open={@auto}
      />
      """
    end
  end

  setup do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "onboard-live-#{id}@dawarich.test",
      api_key: "synthetic-onboard-key"
    })

    %{id: id}
  end

  test "auto-open close persists completion through the owner scope", %{id: id} do
    {:ok, view, html} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "auto" => true}
      )

    assert html =~ ~s(phx-hook="Onboarding")
    assert has_element?(view, "dialog#getting_started[data-native-auto='true']")
    refute render(view) =~ "synthetic-onboard-key"

    view |> element("dialog#getting_started") |> render_hook("onboarding:complete", %{})
    assert completed(id) == true
    refute has_element?(view, "dialog#getting_started[data-native-auto='true']")
  end

  test "manual-only pages never auto-open and revoked owners cannot complete", %{id: id} do
    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "auto" => false}
      )

    assert has_element?(view, "dialog#getting_started[data-native-auto='false']")

    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      id
    ])

    view |> element("dialog#getting_started") |> render_hook("onboarding:complete", %{})
    assert completed(id) == nil
  end

  test "onboarding renders the multipart import controls on the shared native transport", %{
    id: id
  } do
    {:ok, view, _} =
      live_isolated(Phoenix.ConnTest.build_conn(), Host,
        session: %{"user_id" => id, "auto" => true}
      )

    assert has_element?(
             view,
             "#native-onboarding-import-screen form.contents[method=post][enctype='multipart/form-data'][phx-hook=ArchiveChecksum]"
           )

    assert has_element?(
             view,
             "#native-onboarding-upload input[type=file][name='import[files][]'][multiple]"
           )

    assert has_element?(view, "#native-onboarding-upload input[type=submit][disabled]")
    refute has_element?(view, "#native-onboarding-import-screen a[href='/imports/new']")
    assert completed(id) == nil
    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.process_gpx", :oban)

    bytes =
      "<gpx><trk><trkseg><trkpt lat=\"52.5\" lon=\"13.4\"><time>2026-03-01T12:00:00Z</time></trkpt></trkseg></trk></gpx>"

    name = "onboarding-#{id}.gpx"

    input =
      file_input(view, "#native-onboarding-upload", :onboarding_files, [
        %{name: name, content: bytes, type: "application/gpx+xml"}
      ])

    view |> form("#native-onboarding-upload") |> render_change(input)
    [entry] = input.entries

    view
    |> element("#native-onboarding-upload")
    |> render_hook("archive_checksum", %{
      "ref" => entry["ref"],
      "checksum" => Base.encode64(:crypto.hash(:md5, bytes))
    })

    render_upload(input, name, 50)
    view |> element("#native-onboarding-upload") |> render_hook("start_imports", %{})
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1", [id]) == [[0]]
    render_upload(input, name, 50)
    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE filename=$1", [name])
    storage = Dawarich.Imports.StorageContext.storage()
    path = Dawarich.Storage.disk_path(storage.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    assert has_element?(view, "#native-onboarding-upload input[type=submit]:not([disabled])")
    view |> form("#native-onboarding-upload") |> render_submit()
    assert_redirect(view, "/imports")
    assert rows("SELECT name FROM imports WHERE user_id=$1", [id]) == [[name]]

    assert rows(
             "SELECT count(*) FROM active_storage_attachments WHERE record_type='Import' AND record_id IN (SELECT id FROM imports WHERE user_id=$1)",
             [id]
           ) == [[1]]

    assert completed(id) == nil
  end

  defp completed(id),
    do:
      rows("SELECT settings->'onboarding_completed' FROM users WHERE id=$1", [id]) |> hd() |> hd()
end
