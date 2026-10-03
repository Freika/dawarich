defmodule Dawarich.Build.ServedAssetCheckTest do
  use ExUnit.Case, async: true

  alias Dawarich.RailsTree

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

  test "image_smoke.sh asks Rails for the stylesheet path and checks Phoenix and Puma against the image" do
    smoke = RailsTree.read("app-phoenix/scripts/image_smoke.sh")

    assert smoke =~
             ~S|bin/rails runner 'puts ActionController::Base.helpers.asset_path("tailwind.css")'|

    refute smoke =~ "rails_css=\"$(curl"
    assert smoke =~ "served_asset_check.sh"
    assert smoke =~ ~S|for base in http://127.0.0.1:3000 "http://127.0.0.1:$upstream"|
    assert smoke =~ "/var/app/public_dist"

    upstream = :binary.match(smoke, "upstream=\"$(docker logs")
    check = :binary.match(smoke, "served_asset_check.sh")
    assert elem(upstream, 0) < elem(check, 0)
  end
end
