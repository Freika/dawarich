defmodule Dawarich.Build.Sprockets.DirectivesTest do
  use ExUnit.Case, async: true

  alias Dawarich.Build.Sprockets.Directives

  @manifest """
  //= link rails-ujs.js
  //= link_tree ../images
  //= link_tree ../fonts
  //= link_directory ../stylesheets .css
  //= link_tree ../builds
  //= link_tree ../../javascript .js
  //= link_tree ../../../vendor/javascript .js
  //= link favicon/browserconfig.xml
  """

  test "each header directive line becomes one newline and is returned in order" do
    {data, directives} = Directives.split(@manifest)

    assert data == String.duplicate("\n", 8)
    assert hd(directives) == {"link", ["rails-ujs.js"]}
    assert List.last(directives) == {"link", ["favicon/browserconfig.xml"]}
    assert {"link_directory", ["../stylesheets", ".css"]} in directives
  end

  test "keeps other header text, stops at the first code line and ends data with a newline" do
    source = "/*\n *= require_self\n * keep me\n */\n.a{}\n//= require nope"
    {data, directives} = Directives.split(source)

    assert directives == [{"require_self", []}]
    assert data == "/*\n\n * keep me\n */\n.a{}\n//= require nope\n"
  end
end
