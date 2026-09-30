defmodule Dawarich.QrCodeTest do
  use ExUnit.Case, async: true

  alias Dawarich.{QrCode, QrSvg}

  @corpus "test/fixtures/settings_corpus.json" |> File.read!() |> Jason.decode!()

  for %{"payload" => payload, "version" => version} = entry <- @corpus["qr"] do
    @entry entry
    test "version #{version} (#{byte_size(payload)} bytes) matches rqrcode's modules and SVG" do
      entry = @entry
      rows = QrCode.modules(entry["payload"])
      assert length(rows) == entry["version"] * 4 + 17

      assert Enum.map(rows, fn row -> Enum.map_join(row, &if(&1, do: "1", else: "0")) end) ==
               entry["modules"]

      assert QrSvg.svg(entry["payload"]) == entry["svg"]
    end
  end

  test "the API key payload is Rails' to_json of server_url and api_key, & escaped" do
    cases =
      for entry <- @corpus["qr"],
          {:ok, %{"server_url" => url, "api_key" => key}} <- [Jason.decode(entry["payload"])],
          do: {url, key, entry["svg"]}

    assert length(cases) == 4
    assert Enum.any?(cases, fn {url, _, _} -> url =~ "&" end)
    for {url, key, svg} <- cases, do: assert(QrSvg.api_key(url, key) == svg, url)
  end

  test "numeric and alphanumeric data is refused" do
    assert_raise ArgumentError, fn -> QrCode.modules("12345") end
    assert_raise ArgumentError, fn -> QrCode.modules("HELLO WORLD") end
  end

  for %{"root_url" => url} = entry <-
        "test/fixtures/onboarding_qr.json" |> File.read!() |> Jason.decode!() do
    @entry entry
    test "a module-size-3 code for #{url} matches api_key_qr_code(user, size: 3)" do
      assert QrSvg.api_key(@entry["root_url"], @entry["api_key"], 3) == @entry["svg"]
    end
  end
end
