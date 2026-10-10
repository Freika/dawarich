defmodule DawarichWeb.TripsNativeFormTest do
  use Dawarich.DataCase, async: false

  import Phoenix.LiveViewTest

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsMessages
  alias Dawarich.Test.{TripsNativeUI, TripsSeeds}

  setup do
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Dawarich.Repo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, previous) end)
    Ownership.put!(Repo, "command:trips.calculate", :oban)
    TripsSeeds.user!(9_951)
    TripsSeeds.user!(9_952)
    :ok
  end

  defp legacy_blob! do
    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES('k-legacy','legacy.txt','text/plain','{\"identified\":true,\"analyzed\":true}','local',9,'synthetic',now()) RETURNING id"
      )

    id
  end

  defp described_trip!(blob) do
    TripsSeeds.trip!(%{
      id: 995_101,
      user_id: 9_951,
      started_at: ~N[2026-05-09 06:00:00],
      ended_at: ~N[2026-05-12 20:00:00]
    })

    body =
      ~s(<div>Old <action-text-attachment sgid="#{RailsMessages.attachable_sgid(blob)}"></action-text-attachment></div>)

    TripsSeeds.rich_text!(995_101, body)
    [[rich]] = rows("SELECT id FROM action_text_rich_texts WHERE record_id=995101")

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('embeds','ActionText::RichText',$1,$2,now())",
      [rich, blob]
    )

    rich
  end

  defp editor_value(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input[name='trip[rich_description_sgid]']")
    |> LazyHTML.attribute("value")
    |> hd()
  end

  test "trip validation keeps dates name and rich draft without persisting" do
    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/new")
    draft = "<div>Unsaved draft</div>"

    view
    |> form("#trip-form",
      trip: %{name: "", started_at: "2026-05-03T08:00", ended_at: "2026-05-01T08:00"}
    )
    |> render_change(%{"trip" => %{"rich_description_sgid" => draft}})

    html =
      view
      |> form("#trip-form",
        trip: %{name: "", started_at: "2026-05-03T08:00", ended_at: "2026-05-01T08:00"}
      )
      |> render_submit(%{"trip" => %{"rich_description_sgid" => draft}})

    assert html =~ "Name can&#39;t be blank"
    assert has_element?(view, "#error_explanation[role='alert']")
    assert has_element?(view, "input#trip_started_at[value='2026-05-03T08:00']")
    assert has_element?(view, "input#trip_ended_at[value='2026-05-01T08:00']")
    refute_push_event(view, "rich_text:reset", %{})
    assert rows("SELECT count(*) FROM trips WHERE user_id=9951") == [[0]]
    refute :sys.get_state(view.pid).socket.assigns |> inspect() =~ "Unsaved draft"
  end

  test "edited trip retains date zone and attachment graph after reload" do
    blob = legacy_blob!()
    rich = described_trip!(blob)
    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/995101/edit")

    assert has_element?(view, "input#trip_started_at[value='2026-05-09T08:00']")
    assert has_element?(view, "input#trip_ended_at[value='2026-05-12T22:00']")
    value = editor_value(view)
    assert value =~ "data-trix-attachment"

    view
    |> form("#trip-form",
      trip: %{name: "Renamed", started_at: "2026-05-09T08:00", ended_at: "2026-05-12T22:00"}
    )
    |> render_submit(%{
      "trip" => %{"rich_description_sgid" => String.replace(value, "Old", "Edited")}
    })

    flash = assert_redirect(view, "/trips/995101")
    assert flash["notice"] == "Trip was successfully updated."

    assert rows("SELECT name, started_at, ended_at FROM trips WHERE id=995101") ==
             [["Renamed", ~N[2026-05-09 06:00:00.000000], ~N[2026-05-12 20:00:00.000000]]]

    assert [[body]] = rows("SELECT body FROM action_text_rich_texts WHERE id=$1", [rich])
    assert body =~ "Edited"

    assert rows("SELECT blob_id FROM active_storage_attachments WHERE record_id=$1", [rich]) ==
             [[blob]]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  test "trip form rejects stale identity and foreign id before save" do
    TripsSeeds.trip!(%{id: 995_301, user_id: 9_952})

    assert TripsNativeUI.not_found?(9_951, "/trips/995301/edit")
    assert TripsNativeUI.not_found?(9_951, "/trips/99x/edit")

    TripsSeeds.trip!(%{id: 995_302, user_id: 9_951})
    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/995302/edit")
    rows("UPDATE users SET encrypted_password=$1 WHERE id=9951", [String.duplicate("z", 60)])

    assert {:error, {:redirect, %{to: "/users/sign_in"}}} =
             view
             |> form("#trip-form", trip: %{name: "Hijacked"})
             |> render_submit()

    assert rows("SELECT name FROM trips WHERE id=995302") == [["trip 995302"]]
  end

  test "an inactive account cannot open the new trip form; managed trips are read-only" do
    rows("UPDATE users SET active_until='2026-01-01' WHERE id=9952")

    assert {:error, {:redirect, %{to: "/", flash: %{"notice" => notice}}}} =
             TripsNativeUI.live_as(9_952, "/trips/new")

    assert notice =~ "not active"

    TripsSeeds.trip_source!(99_511, 9_951)

    TripsSeeds.trip!(%{
      id: 995_401,
      user_id: 9_951,
      trip_source_id: 99_511,
      source_identifier: "trek-1",
      source_status: 0
    })

    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/995401/edit")
    assert has_element?(view, "input#trip_name[readonly]")
    assert has_element?(view, "input#trip_started_at[readonly]")
  end

  test "form events on an unavailable trip form are ignored" do
    TripsSeeds.trip!(%{id: 995_301, user_id: 9_951})

    rows("UPDATE users SET settings=$1 WHERE id=9951", [
      %{"maps" => %{"distance_unit" => "parsecs"}}
    ])

    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/995301/edit")
    assert has_element?(view, "[role='alert']")

    render_click(view, "validate", %{"trip" => %{"name" => "Changed"}})
    render_click(view, "save", %{"trip" => %{"name" => "Changed"}})

    assert Process.alive?(view.pid)
    assert rows("SELECT name FROM trips WHERE id=995301") == [["trip 995301"]]
  end

  test "the form wires receipt-bound uploads through event replies" do
    {:ok, view, _html} = TripsNativeUI.live_as(9_951, "/trips/new")

    render_hook(view, "rich_upload_reserve", %{
      "name" => "photo.png",
      "size" => 9,
      "type" => "image/png",
      "checksum" => "Xwa4XhYZsri1b3t1igoxCg=="
    })

    assert_reply(view, %{upload_ref: ref, url: _})
    Dawarich.Test.NativeRichUploadFixture.put!(Repo, ref, "synthetic")
    render_hook(view, "rich_upload_claim", %{"upload_ref" => ref})
    assert_reply(view, %{sgid: sgid})
    assert is_binary(sgid)
    refute :sys.get_state(view.pid).socket.assigns |> inspect() =~ sgid
  end
end
