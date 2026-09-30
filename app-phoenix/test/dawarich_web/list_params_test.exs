defmodule DawarichWeb.ListParamsTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.ListParams

  @sortable ~w(name status created_at processed byte_size)

  defp parse(query), do: ListParams.parse(Plug.Conn.Query.decode(query), query, @sortable)

  test "the column and direction Rails' Sortable queries" do
    for {query, column, direction} <- [
          {"", "created_at", :desc},
          {"sort_by=name&order_by=asc", "name", :asc},
          {"sort_by=byte_size", "byte_size", :desc},
          {"sort_by=processed", "processed", :desc},
          {"sort_by=bogus&order_by=asc", "created_at", :asc},
          {"sort_by=NAME", "created_at", :desc},
          {"sort_by=name&order_by=ASC", "name", :desc},
          {"sort_by=name&order_by=sideways", "name", :desc},
          {"sort_by[]=name", "created_at", :desc},
          {"sort_by[a]=name&order_by[]=asc", "created_at", :desc}
        ] do
      assert Map.take(parse(query), [:column, :direction]) == %{
               column: column,
               direction: direction
             },
             query
    end

    assert ListParams.parse(
             %{"sort_by" => "processed"},
             "sort_by=processed",
             ~w(name status created_at byte_size)
           ).column ==
             "created_at"
  end

  test "the header state sortable_column reads from the raw params, as Rack parses them" do
    for {query, current} <- [
          {"", "created_at"},
          {"sort_by", "created_at"},
          {"sort%5Fby", "created_at"},
          {"sort_by=", ""},
          {"sort_by=bogus", "bogus"},
          {"sort_by=name&sort_by", "created_at"},
          {"sort_by&sort_by=name", "name"},
          {"sort_by[]=name", ["name"]}
        ] do
      assert parse(query).current_sort == current, query
    end
  end

  test "Kaminari's page number" do
    for {query, page} <- [
          {"", 1},
          {"page=2", 2},
          {"page=0", 1},
          {"page=-3", 1},
          {"page=2abc", 2},
          {"page=%202", 2},
          {"page=1_0", 10},
          {"page=abc", 1},
          {"page[]=2", 1}
        ] do
      assert parse(query).page == page, query
    end
  end

  test "sort links carry only the next direction and the column, and drop the page" do
    ascending = parse("order_by=asc&sort_by=name&page=3&view=x")

    assert ListParams.sort_href("/imports", "name", ascending) ==
             "/imports?order_by=desc&sort_by=name"

    assert ListParams.sort_href("/imports", "status", ascending) ==
             "/imports?order_by=asc&sort_by=status"

    assert ListParams.sort_href("/exports", "name", parse("sort_by=name")) ==
             "/exports?order_by=asc&sort_by=name"

    assert ListParams.sort_href("/imports", "created_at", parse("order_by=asc")) ==
             "/imports?order_by=desc&sort_by=created_at"
  end
end
