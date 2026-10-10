defmodule DawarichWeb.IconEmbedTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias DawarichWeb.Icon

  @tag :tmp_dir
  test "icons render from the compiled module without reading the Rails asset tree", %{
    tmp_dir: dir
  } do
    root = Application.fetch_env!(:dawarich, :rails_root)
    expected = render_component(&Icon.icon/1, name: "bell", class: "size-6")
    brand = render_component(&Icon.brand/1, name: "google", class: "w-4 h-4")
    Application.put_env(:dawarich, :rails_root, dir)
    on_exit(fn -> Application.put_env(:dawarich, :rails_root, root) end)

    assert render_component(&Icon.icon/1, name: "bell", class: "size-6") == expected
    assert render_component(&Icon.brand/1, name: "google", class: "w-4 h-4") == brand
  end

  test "every embedded icon renders byte-identically to the Rails asset file" do
    root = Dawarich.RailsRoot.join("app/assets/svg/icons")
    outline = Path.wildcard(Path.join(root, "lucide/outline/*.svg"))
    brands = Path.wildcard(Path.join(root, "brands/*.svg"))
    assert length(outline) > 100 and length(brands) > 0

    for path <- outline,
        attrs <- [[], [class: "size-6"], [class: "w-4", aria_hidden: true, id: "probe"]] do
      name = Path.basename(path, ".svg")
      tag = outline_tag(attrs[:class], attrs[:aria_hidden], attrs[:id])
      reference = String.replace(File.read!(path), ~r/<svg[^>]*>/, tag)
      assert render_component(&Icon.icon/1, [name: name] ++ attrs) == reference, name
    end

    for path <- brands do
      name = Path.basename(path, ".svg")

      reference =
        Regex.replace(
          ~r/<svg([^>]*)>/,
          File.read!(path),
          fn _, attrs ->
            ~s(<svg#{Regex.replace(~r/\sclass="[^"]*"/, attrs, "")} class="size-5">)
          end,
          global: false
        )

      assert render_component(&Icon.brand/1, name: name, class: "size-5") == reference, name
    end
  end

  test "the release build copies the embedded icon sets before compiling" do
    builder =
      Path.expand("../../../docker/Dockerfile", __DIR__)
      |> File.read!()
      |> String.split("AS phoenix_builder", parts: 2)
      |> List.last()
      |> String.split("RUN mix release", parts: 2)
      |> List.first()
      |> String.split("\n")

    for set <- ~w(lucide/outline brands) do
      assert "COPY app/assets/svg/icons/#{set} priv/svg_icons/#{set}" in builder
    end
  end

  defp outline_tag(class, aria_hidden, id) do
    ~s(<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round") <>
      if(id, do: ~s( id="#{id}"), else: "") <>
      if(class, do: ~s( class="#{class}"), else: "") <>
      if(aria_hidden, do: ~s( aria-hidden="true"), else: "") <> ">"
  end
end
