defmodule Dawarich.Build.I18nTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.I18n

  @moduletag :tmp_dir

  defp locale!(root, name, text) do
    path = Path.join([root, "config/locales", name])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, text)
  end

  defp export(root), do: root |> I18n.export() |> IO.iodata_to_binary()

  test "merges every config/locales file in sorted path order with Rails' deep-merge positions",
       %{
         tmp_dir: root
       } do
    locale!(root, "z.en.yml", "en:\n  a: 9\n  b:\n    x: 7\n")
    locale!(root, "en.yml", "en:\n  b:\n    y: 2\n  c: [1, 2]\n")
    locale!(root, "0_vendor/01_gem.en.yml", "en:\n  a: 1\n  b:\n    x: 1\n  c: [0]\n")

    assert export(root) == ~s({"en":{"a":9,"b":{"x":7,"y":2},"c":[1,2]}})
  end

  test "orders locales like config.i18n.available_locales and skips the others", %{tmp_dir: root} do
    locale!(root, "a.yml", "it:\n  k: x\nde:\n  k: d\nen:\n  k: e\nzh: ~\n")

    assert export(root) == ~s({"en":{"k":"e"},"de":{"k":"d"},"zh":{}})
  end

  test "refuses Ruby locale files, which hold code Phoenix cannot run", %{tmp_dir: root} do
    locale!(root, "en.yml", "en:\n  k: e\n")
    locale!(root, "extra.rb", "{ en: { k: -> {} } }\n")

    assert_raise ArgumentError, ~r/extra\.rb/, fn -> I18n.export(root) end
  end
end
