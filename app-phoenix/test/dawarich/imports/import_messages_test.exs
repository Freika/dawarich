defmodule Dawarich.Imports.ImportMessagesTest do
  use ExUnit.Case, async: true
  alias Dawarich.Imports.ImportMessages

  test "self-hosted diagnostics and cloud contact are translated inside current owner locale" do
    import = %{name: "sample.gpx"}
    error = RuntimeError.exception("broken")

    local =
      ImportMessages.failure(import, %{locale: "de", self_hosted?: true}, error, [
        "synthetic frame"
      ])

    assert local.title == "Import fehlgeschlagen"

    assert local.content ==
             "Import \"sample.gpx\" fehlgeschlagen: broken, Stacktrace: synthetic frame"

    cloud =
      ImportMessages.failure(import, %{locale: "de", self_hosted?: false}, error, [
        "synthetic frame"
      ])

    assert cloud.content ==
             "Import \"sample.gpx\" fehlgeschlagen, bitte kontaktiere uns unter hi@dawarich.com"

    refute cloud.content =~ "broken"
  end
end
