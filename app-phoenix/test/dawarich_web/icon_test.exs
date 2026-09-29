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
end
