defmodule DawarichWeb.A12f3aRClosureTest do
  use Dawarich.JobsCase

  alias Dawarich.{MapGallery, RailsMessages, RouteVideos}
  alias Dawarich.RouteVideos.{AttachmentEffects, Retention}
  alias Dawarich.Test.{FrameSeeds, ParityHTML}
  import Phoenix.LiveViewTest, only: [render_component: 2]
  import Plug.Conn

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(route_videos))
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag a12f3a_r05: true
  test "R05: native video attachment jobs and cron leaf matches current Rails contract without a native-owner Rails effect" do
    state = capture("r05", "shared_blob")
    user = seed(state)
    blob = hd(state["before"]["active_storage_blobs"])["id"]
    attachment = hd(state["before"]["active_storage_attachments"])

    payload = %{
      "user_id" => user.id,
      "blob_id" => blob,
      "action" => "purge_detached",
      "attachment" => Map.take(attachment, ~w(id name record_type record_id blob_id))
    }

    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob]) == [[1]]
    assert rows("SELECT id FROM oban.oban_jobs") == []
    rows("DELETE FROM active_storage_attachments WHERE blob_id=$1", [blob])
    replacement = Map.put(hd(state["before"]["active_storage_blobs"]), "id", blob + 10)
    replacement = Map.update!(replacement, "key", &(&1 <> "-replacement"))

    Dawarich.Test.ApiGolden.insert!(
      "active_storage_blobs",
      Map.update!(replacement, "metadata", &Jason.encode!/1),
      ScratchRepo
    )

    Dawarich.Test.ApiGolden.insert!(
      "active_storage_attachments",
      Map.put(attachment, "blob_id", blob + 10),
      ScratchRepo
    )

    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob]) == [[1]]
    rows("DELETE FROM active_storage_attachments WHERE id=$1", [attachment["id"]])
    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert :ok = AttachmentEffects.enqueue!(ScratchRepo, payload)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == []

    assert [[%{"objects" => [%{"key" => key, "service_name" => "test"}]}]] =
             rows("SELECT args FROM oban.oban_jobs")

    assert key == hd(state["before"]["active_storage_blobs"])["key"]
    assert rows("SELECT id FROM phoenix.rails_commands") == []
    assert rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob + 10]) == [[1]]
  end

  defp capture(task, name) do
    "test/fixtures/a8vv/videos/a12f3a-#{task}.json"
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("video_" <> name)
  end

  defp seed(state) do
    Dawarich.JobsCase.reset!(ScratchRepo)
    Dawarich.FixtureCleanup.delete!(ScratchRepo, ~w(route_videos))
    before = state["before"]

    FrameSeeds.seed!(
      %{"user" => before["user"], "rows" => Map.drop(before, ["user"])},
      ScratchRepo
    )
  end
end
