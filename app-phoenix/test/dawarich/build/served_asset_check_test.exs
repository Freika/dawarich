defmodule Dawarich.Build.ServedAssetCheckTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @script Path.expand("../../../scripts/served_asset_check.sh", __DIR__)
  @asset "/assets/tailwind-1.css"

  defp tree!(root, name, body) do
    dir = Path.join(root, name)
    File.mkdir_p!(Path.join(dir, "assets"))
    if body, do: File.write!(Path.join(dir, @asset), body)
    dir
  end

  defp check(built, served),
    do:
      System.cmd("/bin/sh", [@script, built, @asset, "file://" <> served, "x"],
        stderr_to_stdout: true
      )

  test "passes when the served bytes are the built bytes", %{tmp_dir: root} do
    assert {"", 0} = check(tree!(root, "built", "a{}"), tree!(root, "served", "a{}"))
  end

  test "fails when the file is missing from the image", %{tmp_dir: root} do
    assert {output, status} = check(tree!(root, "built", nil), tree!(root, "served", "a{}"))
    assert status != 0
    assert output =~ "not in the image"
  end

  test "fails when the built file and the served body are both empty", %{tmp_dir: root} do
    assert {output, status} = check(tree!(root, "built", ""), tree!(root, "served", ""))
    assert status != 0
    assert output =~ "not in the image"
  end

  test "fails when nothing is served", %{tmp_dir: root} do
    assert {_, status} = check(tree!(root, "built", "a{}"), tree!(root, "served", nil))
    assert status != 0
  end

  test "fails when the file is missing from the image and nothing is served", %{tmp_dir: root} do
    assert {_, status} = check(tree!(root, "built", nil), tree!(root, "served", nil))
    assert status != 0
  end

  test "fails when the served bytes are not the built bytes", %{tmp_dir: root} do
    assert {output, status} = check(tree!(root, "built", "a{}"), tree!(root, "served", "b{}"))
    assert status != 0
    assert output =~ "is not the built file"
  end

  @tag :a12f4_a24_1
  test "served asset check resolves candidate CSS from native manifest", %{tmp_dir: root} do
    built = tree!(root, "built", "a{}")
    served = tree!(root, "served", "a{}")
    manifest = Path.join(root, "sprockets-manifest.json")
    File.write!(manifest, Jason.encode!(%{"assets" => %{"tailwind.css" => "tailwind-1.css"}}))
    File.mkdir_p!(Path.join(built, "bin"))
    log = Path.join(root, "rails-called")
    rails = Path.join(built, "bin/rails")
    File.write!(rails, "#!/bin/sh\ntouch '#{log}'\nprintf '/assets/tailwind-1.css\\n'\n")
    File.chmod!(rails, 0o755)

    {output, status} =
      System.cmd(
        "/bin/sh",
        [@script, "--stylesheet", built, manifest, "file://" <> served, "x"],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute File.exists?(log)

    File.write!(manifest, Jason.encode!(%{"assets" => %{}}))

    {output, status} =
      System.cmd(
        "/bin/sh",
        [@script, "--stylesheet", built, manifest, "file://" <> served, "x"],
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "tailwind.css is missing from the native manifest"
  end
end
