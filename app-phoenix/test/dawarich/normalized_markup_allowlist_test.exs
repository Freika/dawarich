defmodule Dawarich.NormalizedMarkupAllowlistTest do
  use ExUnit.Case, async: true
  alias Dawarich.Test.ParityHTML

  test "native-prefixed ids and native map wiring do not count as markup" do
    rails = ~s(<div class="map w-full"><input type="search" class="input"></div>)

    native =
      ~s(<div id="native-map" phx-hook="Map" data-map-config="{}" data-native-map-root class="map w-full">) <>
        ~s(<input id="native-map-search" phx-update="ignore" data-map-search type="search" class="input"></div>)

    assert ParityHTML.normalize(native) == ParityHTML.normalize(rails)
  end

  test "a Turbo frame counts only through its contents" do
    assert ParityHTML.normalize(
             ~s(<div><turbo-frame id="x" class="contents"><span class="a"></span></turbo-frame></div>)
           ) ==
             ParityHTML.normalize(~s(<div><span class="a"></span></div>))
  end

  test "an accessible name on a form control counts as an addition, not as markup" do
    assert ParityHTML.normalize(~s(<input type="text" aria-label="Search" class="input">)) ==
             ParityHTML.normalize(~s(<input type="text" class="input">))

    refute ParityHTML.normalize(~s(<button type="button" aria-label="Close"></button>)) ==
             ParityHTML.normalize(~s(<button type="button"></button>))
  end

  test "ids, classes and other data attributes still count" do
    refute ParityHTML.normalize(~s(<div id="map" class="a"></div>)) ==
             ParityHTML.normalize(~s(<div class="a"></div>))

    refute ParityHTML.normalize(~s(<div id="chart" phx-update="ignore"></div>)) ==
             ParityHTML.normalize(~s(<div></div>))

    refute ParityHTML.normalize(~s(<div data-theme="dark"></div>)) ==
             ParityHTML.normalize(~s(<div></div>))

    refute ParityHTML.normalize(~s(<div class="a b"></div>)) ==
             ParityHTML.normalize(~s(<div class="a"></div>))
  end
end
