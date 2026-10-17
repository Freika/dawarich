defmodule Dawarich.Build.RailsConfigTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.{I18n, Sprockets.Writer}

  test "the exported locales are the ones Rails makes available, in Rails' order" do
    assert I18n.locales() == ~w(en de es fr pl ca zh)
  end

  test "asset digests carry the version Rails is configured with" do
    source = "body{}"
    expected = :crypto.hash(:sha256, "1.0" <> :crypto.hash(:sha256, source))
    assert Writer.etag(source) == Base.encode16(expected, case: :lower)
  end
end
