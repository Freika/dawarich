defmodule Dawarich.Build.Sprockets.ProcessorsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Sprockets.Processors

  test "JavaScript parts get Sprockets' semicolon: before a final newline, space or tab, else appended" do
    assert Processors.concat_js(["a\n", "b", "c;\n", "d; \n", "e\r", "", "  \n"]) ==
             "a;\nb;c;\nd; \ne\r;  \n"
  end

  test "url() rewriting skips #, data and http, strips ./, drops quotes and keeps query tails" do
    text =
      ~s[a{b:url('x.woff2?v=4') url(data:a) url("#f") url(http://h/x) url( ./y.png ) url(/abs.png)}]

    assert Processors.url_paths(text) == ["x.woff2?v=4", "y.png", "/abs.png"]

    urls = %{
      "x.woff2?v=4" => "/assets/x-1.woff2?v=4",
      "y.png" => "/assets/y-2.png",
      "/abs.png" => "/abs.png"
    }

    assert Processors.rewrite_urls(text, urls) ==
             ~s[a{b:url(/assets/x-1.woff2?v=4) url(data:a) url("#f") url(http://h/x) url(/assets/y-2.png) url(/abs.png)}]
  end

  @tag :tmp_dir
  test "a UTF-8 BOM always goes, a leading @charset only from CSS", %{tmp_dir: dir} do
    path = Path.join(dir, "x.css")
    File.write!(path, <<0xEF, 0xBB, 0xBF>> <> ~s(@charset "UTF-8";\na{}\n))

    assert Processors.read_text(path, :css) == "\na{}\n"
    assert Processors.read_text(path, :js) == ~s(@charset "UTF-8";\na{}\n)
  end

  test "sourceMappingURL comments are found, replaced whole, and resolved beside the source" do
    text = "x;\n//# sourceMappingURL=a.js.map\n"

    assert Processors.sourcemap_refs(text) == ["a.js.map"]
    assert Processors.rewrite_sourcemaps(text, %{"a.js.map" => ""}) == "x;\n\n"
    assert Processors.sibling("controllers/a.js", "a.js.map") == "controllers/a.js.map"
    assert Processors.sibling("a.js", "a.js.map") == "a.js.map"
    assert Processors.split_tail("a.png?v=1#x") == {"a.png", "?v=1#x"}
  end

  test "ERB assets may only call asset_path" do
    text = ~s[src="<%= asset_path 'a.png' %>" url(<%= asset_path("b.woff2") %>)]

    assert Processors.erb_paths(text, "f") == ["a.png", "b.woff2"]

    assert Processors.render_erb(text, %{
             "a.png" => "/assets/a-1.png",
             "b.woff2" => "/assets/b-2.woff2"
           }) ==
             ~s[src="/assets/a-1.png" url(/assets/b-2.woff2)]

    assert_raise ArgumentError, fn -> Processors.erb_paths("x <%= image_path 'y' %>", "f") end
    assert_raise ArgumentError, fn -> Processors.erb_paths("<% if x %>\n", "f") end
  end
end
