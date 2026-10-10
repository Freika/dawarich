defmodule DawarichWeb.NativeM6IntegrationRegisterTest do
  use ExUnit.Case, async: true

  test "native map integration records every B patch difference and Notes handoff" do
    diffs = File.read!(Path.expand("../../parity/expected_diffs.md", __DIR__))
    contracts = File.read!(Path.expand("../../../docs/phoenix/native-m6-contracts.md", __DIR__))
    for id <- ~w(B4-noted-merge B4-visit-notes B8-integer-cast B10-year-zone B15-playback-clock),
      do: assert(diffs =~ "ED-NATIVE-M6-#{id}")
    assert diffs =~ "typed `unsupported`"
    assert diffs =~ "profile time zone"
    assert contracts =~ "Dawarich.Maps.Dependencies.Notes"
    assert contracts =~ "NotesApi.Read.index/3"
    assert contracts =~ "m5 notes/ActionText"
  end
end
