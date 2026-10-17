defmodule Dawarich.MapGalleryTest do
  use Dawarich.JobsCase, async: false

  alias Dawarich.MapGallery
  alias Dawarich.Test.MapSeeds
  alias DawarichWeb.LocalizedTime

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
  end

  test "the ten newest posters and videos with their files; a video's date in the user's zone" do
    user = MapSeeds.seed!(MapSeeds.load("cloud_pro_en"))
    [rendering, done, failed] = MapGallery.posters(user.id)
    assert {rendering.id, done.id, failed.id} == {6302, 6301, 6303}

    assert done.files == %{
             "image" => %{id: 6401, filename: "poster 6301.png"},
             "print_pdf" => %{id: 6402, filename: "poster:6301;print.pdf"}
           }

    assert rendering.files == %{"image" => nil, "print_pdf" => nil}
    assert rendering.settings == %{"progress_phase" => "drawing_route"}

    [stored, expired] = MapGallery.route_videos(user.id, "Europe/Berlin")
    assert stored.files["file"] == %{id: 6601, filename: "trip ü video.mp4"}
    assert expired.shown_at == ~N[2026-09-01 20:30:00]

    assert expired.settings_json ==
             "{\"zoom\":1.5,\"title\":\"\\u003cb\\u003eTom \\u0026 Jerry\\u003c/b\\u003e\",\"format\":\"landscape\"}"
  end

  test "a poster's settings in the gallery are trimmed to progress_phase and error" do
    user = MapSeeds.seed!(MapSeeds.load("cloud_pro_en"))

    Dawarich.Repo.query!(
      ~s(UPDATE posters SET settings = settings || '{"lat": 52.5, "lon": 13.4, "distance": 10}' WHERE id = $1),
      [6302]
    )

    [rendering | _] = MapGallery.posters(user.id)
    assert rendering.settings == %{"progress_phase" => "drawing_route"}
  end

  test "time.formats.long with Rails' month names" do
    assert LocalizedTime.l("en", ~N[2026-09-01 20:30:00], "long") == "September 01, 2026 20:30"
  end
end
