defmodule Dawarich.Build.RailsConfigTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.{I18n, Sprockets.Writer}
  alias Dawarich.RailsTree

  test "the exported locales are the ones Rails makes available, in Rails' order" do
    [_, listed] =
      Regex.run(
        ~r/config\.i18n\.available_locales = %i\[([^\]]*)\]/,
        RailsTree.read("config/application.rb")
      )

    assert I18n.locales() == String.split(listed)
  end

  test "asset digests carry the version Rails is configured with" do
    [_, version] =
      Regex.run(
        ~r/config\.assets\.version = '([^']*)'/,
        RailsTree.read("config/initializers/assets.rb")
      )

    source = "body{}"
    expected = :crypto.hash(:sha256, version <> :crypto.hash(:sha256, source))

    assert Writer.etag(source) == Base.encode16(expected, case: :lower)
  end
end
