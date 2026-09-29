defmodule Dawarich.HtmlSanitizerTest do
  use ExUnit.Case, async: true

  alias Dawarich.HtmlSanitizer
  alias Dawarich.Test.ParityHTML

  for %{"input" => input, "output" => output} <-
        "test/fixtures/sanitize.json" |> File.read!() |> Jason.decode!() do
    @input input
    @output output
    test "sanitizes #{inspect(input)} as Rails does" do
      assert ParityHTML.normalize(HtmlSanitizer.sanitize(@input)) == ParityHTML.normalize(@output)
    end
  end

  test "never emits a script element or an event handler" do
    html =
      HtmlSanitizer.sanitize(
        ~s[<script>alert(1)</script><img src=x onerror=alert(1)><a href="javascript:x">y</a>]
      )

    refute html =~ "<script"
    refute html =~ "onerror"
    refute html =~ "javascript:"
  end

  test "an empty string stays empty" do
    assert HtmlSanitizer.sanitize("") == ""
  end
end
