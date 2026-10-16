defmodule Dawarich.Test.ParityFlashTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.ParityHTML

  test "flash comparison ignores presentation only and preserves type role text controls and other markup" do
    rails =
      ~s(<turbo-stream action="append" target="flash-messages"><template><div role="alert" class="alert alert-success shadow-lg"><div class="flex"><span class="text-sm">Saved &amp; ready</span></div><button aria-label="Close" class="btn">Close</button></div></template></turbo-stream><p class="unrelated">Retained</p>)

    native =
      rails
      |> String.replace("shadow-lg", "native-flash pointer-events-none max-w-full")
      |> String.replace("class=\"flex\"", "class=\"flex min-w-0\"")
      |> String.replace("text-sm", "break-words")
      |> String.replace("class=\"btn\"", "class=\"btn pointer-events-auto\"")

    assert ParityHTML.normalize_flash(native) == ParityHTML.normalize_flash(rails)

    for {from, to} <- [
          {"alert-success", "alert-error"},
          {"role=\"alert\"", "role=\"status\""},
          {"Saved &amp; ready", "Failed"},
          {"aria-label=\"Close\"", "aria-label=\"Open\""},
          {"target=\"flash-messages\"", "target=\"elsewhere\""},
          {"unrelated", "changed"},
          {"<button", "<a"}
        ] do
      refute ParityHTML.normalize_flash(String.replace(native, from, to)) ==
               ParityHTML.normalize_flash(rails),
             from
    end
  end
end
