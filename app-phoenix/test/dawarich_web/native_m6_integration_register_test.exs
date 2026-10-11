defmodule DawarichWeb.NativeM6IntegrationRegisterTest do
  use ExUnit.Case, async: true

  test "native map integration records B differences and native Notes contexts without an adapter" do
    diffs = File.read!(Path.expand("../../parity/expected_diffs.md", __DIR__))
    contracts = File.read!(Path.expand("../../../docs/phoenix/native-m6-contracts.md", __DIR__))

    for id <- ~w(B4-noted-merge B4-visit-notes B8-integer-cast B10-year-zone B15-playback-clock),
        do: assert(diffs =~ "ED-NATIVE-M6-#{id}")

    assert diffs =~ "typed `unsupported`"
    assert diffs =~ "profile time zone"
    assert contracts =~ "Dawarich.Trips.Notes"
    refute File.exists?(Path.expand("../../lib/dawarich/maps/dependencies/notes.ex", __DIR__))
    assert contracts =~ "NotesApi.Read.index/3"
    assert contracts =~ "m5 notes/ActionText"
  end

  test "native map styles use the real integrated poster modules without a dependency adapter" do
    refute File.exists?(Path.expand("../../assets/js/map/style/dependencies.js", __DIR__))
    source = File.read!(Path.expand("../../assets/js/map/style/map_style.js", __DIR__))
    assert source =~ "poster/data/theme_loader.js"
    assert source =~ "poster/render/style_builder.js"
  end

  test "studio operation bounds are frozen without changing media formats" do
    contracts = File.read!(Path.expand("../../../docs/phoenix/native-m6-contracts.md", __DIR__))

    for bound <- [
          "first idle: 60 seconds",
          "negotiation: 30 seconds",
          "hook reply: 30 seconds",
          "upload: 1 byte–250 MiB",
          "gallery: 10 rows"
        ],
        do: assert(contracts =~ bound)
  end

  test "integrated poster and video handoffs have complete ED FRB and changelog rows" do
    diffs = File.read!(Path.expand("../../parity/expected_diffs.md", __DIR__))
    bugs = File.read!(Path.expand("../../../docs/phoenix/fixed-rails-bugs.md", __DIR__))
    changes = File.read!(Path.expand("../../../docs/phoenix/CHANGELOG-phoenix-draft.md", __DIR__))

    for suffix <-
          ~w(POSTER-EXPORT-CLOSE POSTER-EXPORT-HANG POSTER-EXPORT-CONTAINER POSTER-ORDER-HANG POSTER-CHECKOUT-URL POSTER-RANGE-ERROR VIDEO-CONSTRUCTION VIDEO-FIRST-IDLE VIDEO-ABANDONED-UPLOAD VIDEO-CODEC-WAIT VIDEO-UPLOAD-WAIT VIDEO-THEME-ORDER VIDEO-RECIPE-SNAPSHOT VIDEO-CONFIGURE-CLOSE VIDEO-FORMAT-OWN-KEY) do
      assert diffs =~ "ED-NATIVE-M6-#{suffix}"
      assert bugs =~ "FRB-NATIVE-M6-#{suffix}"
      assert changes =~ "FRB-NATIVE-M6-#{suffix}"
    end

    for suffix <-
          ~w(POSTER-STUDIO POSTER-GALLERY POSTER-LIMITS POSTER-CHECKOUT VIDEO-a VIDEO-b VIDEO-c VIDEO-d VIDEO-e),
        do: assert(diffs =~ "ED-NATIVE-M6-#{suffix}")

    assert diffs =~ "empty recipe"
  end

  test "native trip photo credential refusal has its ED FRB and changelog provenance" do
    diffs = File.read!(Path.expand("../../parity/expected_diffs.md", __DIR__))
    bugs = File.read!(Path.expand("../../../docs/phoenix/fixed-rails-bugs.md", __DIR__))
    changes = File.read!(Path.expand("../../../docs/phoenix/CHANGELOG-phoenix-draft.md", __DIR__))
    assert diffs =~ "ED-NATIVE-M6-TRIP-PHOTO-LINK"
    assert bugs =~ "FRB-NATIVE-M6-TRIP-PHOTO-LINK"
    assert bugs =~ "app/helpers/trips_helper.rb:11"
    assert changes =~ "FRB-NATIVE-M6-TRIP-PHOTO-LINK"
  end

  test "native trip dependent cleanup fix has its ED FRB and changelog provenance" do
    diffs = File.read!(Path.expand("../../parity/expected_diffs.md", __DIR__))
    bugs = File.read!(Path.expand("../../../docs/phoenix/fixed-rails-bugs.md", __DIR__))
    changes = File.read!(Path.expand("../../../docs/phoenix/CHANGELOG-phoenix-draft.md", __DIR__))
    assert diffs =~ "ED-NATIVE-M6-TRIP-DEPENDENTS"
    assert bugs =~ "FRB-NATIVE-M6-TRIP-DEPENDENTS"
    assert bugs =~ "app/models/concerns/notable.rb:7"
    assert changes =~ "FRB-NATIVE-M6-TRIP-DEPENDENTS"
  end
end
