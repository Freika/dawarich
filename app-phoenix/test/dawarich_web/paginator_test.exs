defmodule DawarichWeb.PaginatorTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias DawarichWeb.{Paginator, Params}

  test "one page renders nothing and neighbours carry rel" do
    assert Paginator.tags(1, 1) == []
    assert Paginator.tags(1, 2) == [{:page, 1}, {:page, 2}, :next]
    assert Paginator.tags(2, 2) == [:prev, {:page, 1}, {:page, 2}]
  end

  test "the window is four pages, outer pages collapse into one gap, a single-page gap shows the page" do
    assert Paginator.tags(7, 13) ==
             [:prev, :gap] ++ Enum.map(3..11, &{:page, &1}) ++ [:gap, :next]

    assert Paginator.tags(6, 13) |> Enum.take(3) == [:prev, {:page, 1}, {:page, 2}]
    assert Paginator.tags(20, 13) == [:prev, :gap]
  end

  test "links keep the query sorted, drop page 1 and the form keys" do
    html =
      render_component(&Paginator.paginator/1,
        locale: "en",
        path: "/notifications",
        query: %{"locale" => "de", "page" => "2", "_method" => "x"},
        page: 2,
        total_pages: 3
      )

    assert html =~ ~s(href="/notifications?locale=de")
    assert html =~ ~s(href="/notifications?locale=de&amp;page=3")
    assert html =~ ~s(<button class="join-item btn btn-active">2</button>)
  end

  test "plain links append the anchor and leave out the LiveView patch" do
    html =
      render_component(&Paginator.paginator/1,
        locale: "en",
        path: "/achievements/continent_europe",
        query: %{"q" => " a ", "page" => "2", "status" => "locked"},
        page: 2,
        total_pages: 3,
        anchor: "collection",
        patch: false
      )

    assert html =~ ~s(href="/achievements/continent_europe?q=+a+&amp;status=locked#collection")

    assert html =~
             ~s(href="/achievements/continent_europe?page=3&amp;q=+a+&amp;status=locked#collection")

    refute html =~ "data-phx-link"
  end

  test "ruby_to_i reads leading digits like String#to_i" do
    for {input, value} <- [
          {"2", 2},
          {" 3x", 3},
          {"+4", 4},
          {"-1", -1},
          {"1_000", 1000},
          {"1__0", 1},
          {"_1", 0},
          {"abc", 0},
          {nil, 0},
          {["2"], 0}
        ],
        do: assert(Params.ruby_to_i(input) == value)
  end

  test "to_query encodes nested params as Rails' Hash#to_query does" do
    for {params, query} <- [
          {%{"x" => ["1"], "locale" => "de"}, "locale=de&x%5B%5D=1"},
          {%{"page" => "2", "x" => %{"b" => "1", "a" => "2"}, "locale" => "de"},
           "locale=de&page=2&x%5Ba%5D=2&x%5Bb%5D=1"},
          {%{"a b" => "1", "a" => "2", "locale" => "de"}, "a+b=1&a=2&locale=de"},
          {%{"e" => [], "h" => %{}, "n" => %{"y" => []}, "locale" => "de"}, "&locale=de"},
          {%{"q" => "Straße & ~*", "locale" => "de"}, "locale=de&q=Stra%C3%9Fe+%26+~%2A"},
          {%{"x" => ["2", "1"], "locale" => "de"}, "locale=de&x%5B%5D=2&x%5B%5D=1"}
        ],
        do: assert(Params.to_query(params) == query)
  end
end
