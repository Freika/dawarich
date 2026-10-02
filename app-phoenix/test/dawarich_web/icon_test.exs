defmodule DawarichWeb.IconTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  test "icons come from the Rails root, the working directory in the image" do
    root = Application.fetch_env!(:dawarich, :rails_root)
    Application.delete_env(:dawarich, :rails_root)
    on_exit(fn -> Application.put_env(:dawarich, :rails_root, root) end)

    html =
      File.cd!(root, fn ->
        render_component(&DawarichWeb.Icon.icon/1, name: "bell", class: "size-6")
      end)

    assert html =~ ~s(class="size-6")
    assert html =~ "<path"
  end

  test "a brand icon is rails_icons' brands SVG with the given class and no stroke width" do
    html = render_component(&DawarichWeb.Icon.brand/1, name: "google", class: "w-4 h-4")

    assert hd(Regex.run(~r/<svg[^>]*>/, html)) ==
             ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" class="w-4 h-4">)

    assert length(String.split(html, "<path")) == 5
    refute html =~ "stroke-width"
  end

  test "aria_hidden adds aria-hidden=true, as rails_icons does for aria: { hidden: true }" do
    html =
      render_component(&DawarichWeb.Icon.icon/1,
        name: "play",
        class: "w-5 h-5",
        aria_hidden: true
      )

    assert html =~ ~s(class="w-5 h-5" aria-hidden="true")
    refute render_component(&DawarichWeb.Icon.icon/1, name: "play") =~ "aria-hidden"
  end

  test "a brand icon with a class baked into its own source keeps only the caller's class" do
    html = render_component(&DawarichWeb.Icon.brand/1, name: "airtrail", class: "size-5 shrink-0")
    tag = hd(Regex.run(~r/<svg[^>]*>/, html))

    assert Regex.scan(~r/\sclass="/, tag) |> length() == 1
    assert tag =~ ~s(class="size-5 shrink-0">)
    refute tag =~ "lucide-tower-control"
    assert tag =~ ~s(stroke="#3c83f6")
  end
end
