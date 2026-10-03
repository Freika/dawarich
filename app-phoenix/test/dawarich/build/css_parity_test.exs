defmodule Dawarich.Build.CssParityTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("../../../scripts/css_parity.mjs", __DIR__)
  @pages ["/stats", "/notifications", "/settings/general"]
  @old String.duplicate("a", 64)
  @new String.duplicate("b", 64)

  defp sheet(name, digest, body), do: ["/assets/#{name}-#{digest}.css", body]

  defp capture(sheets, styles),
    do: Map.new(@pages, &{&1, %{"sheets" => sheets, "styles" => styles}})

  defp compare(root, left, right, flags \\ []) do
    [a, b] =
      for {name, data} <- [left: left, right: right] do
        path = Path.join(root, "#{name}.json")
        File.write!(path, Jason.encode!(data))
        path
      end

    System.cmd("node", [@script, "compare", a, b | flags], stderr_to_stdout: true)
  end

  defp styles(extra \\ %{}), do: Map.merge(%{"div#.box@1" => "block", "p#.@1" => "red"}, extra)

  defp base, do: capture([sheet("tailwind", @old, "h1")], styles())

  test "identical captures pass", %{tmp_dir: root} do
    assert {_, 0} = compare(root, base(), base())
    assert {_, 0} = compare(root, base(), base(), ["--strict"])
  end

  test "a stylesheet whose body changed behind a new digest is a difference", %{tmp_dir: root} do
    changed = capture([sheet("tailwind", @new, "h2")], styles())

    assert {output, 1} = compare(root, base(), changed)
    assert output =~ "tailwind.css: body differs"
  end

  test "a stylesheet with the same body under another digest is not", %{tmp_dir: root} do
    renamed = capture([sheet("tailwind", @new, "h1")], styles())

    assert {_, 0} = compare(root, base(), renamed)
  end

  test "captures with no stylesheet in common fail", %{tmp_dir: root} do
    other = capture([sheet("application", @old, "h1")], styles())

    assert {output, 1} = compare(root, base(), other)
    assert output =~ "no stylesheet in common"
  end

  test "captures with no element in common fail", %{tmp_dir: root} do
    other = capture([sheet("tailwind", @old, "h1")], %{"span#.x@1" => "inline"})

    assert {output, 1} = compare(root, base(), other)
    assert output =~ "no element in common"
  end

  test "a shared element with another computed style fails", %{tmp_dir: root} do
    other = capture([sheet("tailwind", @old, "h1")], styles(%{"div#.box@1" => "flex"}))

    assert {output, 1} = compare(root, base(), other)
    assert output =~ "div#.box@1: block -> flex"
  end

  test "elements and stylesheets on one side only fail only under --strict", %{tmp_dir: root} do
    extra_element = capture([sheet("tailwind", @old, "h1")], styles(%{"a#.x@1" => "inline"}))

    extra_sheet =
      capture([sheet("tailwind", @old, "h1"), sheet("trix", @old, "t")], styles())

    for other <- [extra_element, extra_sheet] do
      assert {_, 0} = compare(root, base(), other)
      assert {_, 0} = compare(root, other, base())
      assert {_, 1} = compare(root, base(), other, ["--strict"])
      assert {_, 1} = compare(root, other, base(), ["--strict"])
    end
  end
end
