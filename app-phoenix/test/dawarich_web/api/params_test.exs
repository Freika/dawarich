defmodule DawarichWeb.Api.ParamsTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias Dawarich.Distance
  alias DawarichWeb.Api.Params

  test "year: absent, a four-digit string or an integer in 1970..2037; anything else goes to Rails" do
    assert {Params.year(nil), Params.year("2024"), Params.year(2024), Params.year("2037")} ==
             {{:ok, nil}, {:ok, 2024}, {:ok, 2024}, {:ok, 2037}}

    for value <- [
          "",
          "abc",
          "20245",
          "2024 ",
          " 2024",
          "1969",
          "2038",
          "0999",
          "2_024",
          2038,
          12.5,
          ["2024"]
        ],
        do: assert({:replay, _} = Params.year(value), inspect(value))
  end

  test "unit: a present parameter, else settings.maps.distance_unit, else km; only Rails' five units" do
    assert Params.unit("mi", %{}) == {:ok, "mi"}
    assert Params.unit(nil, %{"maps" => %{"distance_unit" => "ft"}}) == {:ok, "ft"}
    assert Params.unit(" ", %{"maps" => %{"distance_unit" => "yd"}}) == {:ok, "yd"}

    for settings <- [
          %{},
          %{"maps" => nil},
          %{"maps" => %{}},
          %{"maps" => %{"distance_unit" => false}},
          ["x"],
          nil
        ],
        do: assert(Params.unit(nil, settings) == {:ok, "km"}, inspect(settings))

    for {param, settings} <- [
          {"furlong", %{}},
          {"KM", %{}},
          {5, %{}},
          {nil, %{"maps" => %{"distance_unit" => "KM"}}},
          {nil, %{"maps" => %{"distance_unit" => 5}}},
          {nil, %{"maps" => "x"}},
          {nil, %{"maps" => false}}
        ],
        do: assert({:replay, _} = Params.unit(param, settings), inspect({param, settings}))
  end

  test "min_minutes: Ruby's (value || 60).to_i for integers, floats and digit strings" do
    for {settings, minutes} <- [
          {%{}, 60},
          {%{"min_minutes_spent_in_city" => nil}, 60},
          {%{"min_minutes_spent_in_city" => false}, 60},
          {%{"min_minutes_spent_in_city" => 30}, 30},
          {%{"min_minutes_spent_in_city" => 45.9}, 45},
          {%{"min_minutes_spent_in_city" => "90"}, 90},
          {"not a map", 60}
        ],
        do: assert(Params.min_minutes(settings) == {:ok, minutes}, inspect(settings))

    for value <- ["abc", "30min", " 30", true, %{}, []],
        do:
          assert(
            {:replay, _} = Params.min_minutes(%{"min_minutes_spent_in_city" => value}),
            inspect(value)
          )
  end

  test "timestamp: digit strings are epochs; ISO dates and offset date-times are parsed in the zone later; the rest goes to Rails" do
    assert Params.timestamp("1700000000") == {:ok, {:epoch, 1_700_000_000}}

    for text <- [
          "2024-03-01",
          "2024-03-01T10:00+01:00",
          "2024-03-01T10:00:05Z",
          "2024-03-01T10:00:05.123456-03:30",
          "2024-02-29"
        ],
        do: assert(Params.timestamp(text) == {:ok, {:text, text}}, text)

    for value <- [
          "2024-02-30",
          "2023-02-29",
          "2024-03-01T24:00+01:00",
          "2024-03-01T10:60Z",
          "yesterday",
          "2024-03-01T10:00:00.1234567Z",
          "-5",
          "2024-03-01T10:00+15:00",
          "2024-3-1",
          17,
          nil
        ],
        do: assert({:replay, _} = Params.timestamp(value), inspect(value))
  end

  test "flight_filter: no filter when both are blank, nil for one blank side, the text otherwise" do
    assert Params.flight_filter(nil, "") == {:ok, :none}
    assert Params.flight_filter(nil, "2024-03-31") == {:ok, {nil, "2024-03-31"}}

    assert Params.flight_filter("2024-03-01T00:00+01:00", " ") ==
             {:ok, {"2024-03-01T00:00+01:00", nil}}

    assert {:replay, _} = Params.flight_filter("March 1 2024", nil)
    assert {:replay, _} = Params.flight_filter(nil, 1_700_000_000)
  end

  test "missing: blank required parameters in the order given" do
    assert Params.missing(%{}, ~w(start_at end_at)) == ~w(start_at end_at)

    assert Params.missing(%{"start_at" => "1", "end_at" => " "}, ~w(start_at end_at)) ==
             ~w(end_at)

    assert Params.missing(%{"start_at" => 5, "end_at" => "1"}, ~w(start_at end_at)) == []
  end

  test "If-Modified-Since: absent, or one IMF-fixdate with a real date; http_date prints Rails' httpdate" do
    at = fn headers -> Params.if_modified_since(%{conn(:get, "/") | req_headers: headers}) end

    assert at.([]) == {:ok, nil}

    assert at.([{"if-modified-since", " Sun, 06 Nov 1994 08:49:37 GMT "}]) ==
             {:ok, ~N[1994-11-06 08:49:37]}

    assert at.([{"if-modified-since", "Mon, 06 Nov 1994 08:49:37 GMT"}]) ==
             {:ok, ~N[1994-11-06 08:49:37]}

    for headers <- [
          [{"if-modified-since", "Sunday, 06-Nov-94 08:49:37 GMT"}],
          [{"if-modified-since", "Sun, 31 Feb 1994 08:49:37 GMT"}],
          [{"if-modified-since", "06 Nov 1994 08:49:37 +0000"}],
          [
            {"if-modified-since", "Sun, 06 Nov 1994 08:49:37 GMT"},
            {"if-modified-since", "Sun, 06 Nov 1994 08:49:37 GMT"}
          ]
        ],
        do: assert({:replay, _} = at.(headers), inspect(headers))

    assert Params.http_date(~N[1994-11-06 08:49:37.123456]) == "Sun, 06 Nov 1994 08:49:37 GMT"
  end

  test "Distance: Rails' DISTANCE_UNITS and convert_distance" do
    assert Enum.filter(~w(km mi m ft yd KM furlong), &Distance.unit?/1) == ~w(km mi m ft yd)

    assert {Distance.convert(1609, "km"), Distance.convert(160_934, "mi"),
            Distance.convert(7, "m")} == {1.609, 160_934 / 1609.34, 7.0}
  end

  test "coordinates: present decimal text read as Ruby's to_f; blank is :missing; other shapes go to Rails without the value in the reason" do
    assert Params.coordinates("52.52", "13.405") == {:ok, 52.52, 13.405}
    assert Params.coordinates("-90", "180") == {:ok, -90.0, 180.0}
    assert {:ok, 1.0e-7, lon} = Params.coordinates("1e-7", "-0")
    assert <<1::1, _::63>> = <<lon::float>>

    for {lat, lon} <- [{nil, "13"}, {"52", nil}, {"", "13"}, {"52", " "}],
        do: assert(Params.coordinates(lat, lon) == :missing, inspect({lat, lon}))

    for {lat, lon} <- [
          {"52.5abc", "13"},
          {"52,5", "13"},
          {"+52", "13"},
          {" 52", "13"},
          {"52.", "13"},
          {".5", "13"},
          {"1e3", "13"},
          {"1000", "13"},
          {"52", "0x1A"},
          {52.5, "13"},
          {"52", ["13"]}
        ] do
      assert Params.coordinates(lat, lon) == {:replay, "coordinate parameter shape"},
             inspect({lat, lon})
    end
  end

  test "count: absent is the default, one to nine digits are the integer, anything else goes to Rails" do
    assert {Params.count(nil, 50), Params.count("0", 50), Params.count("007", 50),
            Params.count("123456789", 500)} ==
             {{:ok, 50}, {:ok, 0}, {:ok, 7}, {:ok, 123_456_789}}

    for value <- ["", " 5", "5 ", "-1", "+5", "1.5", "5abc", "1234567890", 5, ["5"]],
        do: assert({:replay, _} = Params.count(value, 50), inspect(value))
  end

  test "date: blank is nil, a real YYYY-MM-DD in 1970..2037 is a Date, anything else goes to Rails" do
    assert {Params.date(nil), Params.date(""), Params.date("  "), Params.date("2023-11-15"),
            Params.date("2037-12-31")} ==
             {{:ok, nil}, {:ok, nil}, {:ok, nil}, {:ok, ~D[2023-11-15]}, {:ok, ~D[2037-12-31]}}

    for value <- [
          "2023-02-30",
          "2023-13-01",
          "1969-12-31",
          "2038-01-01",
          "2023-1-5",
          "Nov 15 2023",
          "2023-11-15T00:00",
          "20231115",
          2023,
          ["2023-11-15"]
        ],
        do: assert({:replay, _} = Params.date(value), inspect(value))
  end

  test "text: nil or a string passes, anything else goes to Rails" do
    assert {Params.text(nil), Params.text(""), Params.text("Café <Z>")} ==
             {{:ok, nil}, {:ok, ""}, {:ok, "Café <Z>"}}

    for value <- [1, ["a"], %{"a" => 1}, true],
        do: assert({:replay, "text parameter shape"} = Params.text(value), inspect(value))
  end

  test "rejected count and date values never appear in replay reasons" do
    secret = "phoenix-a4g3-sensitive-query"
    assert Params.count(secret, 50) == {:replay, "count parameter shape"}
    assert Params.date(secret) == {:replay, "date parameter shape"}
    assert Params.date("1969-12-31") == {:replay, "date parameter shape"}
  end
end
