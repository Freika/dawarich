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
end
