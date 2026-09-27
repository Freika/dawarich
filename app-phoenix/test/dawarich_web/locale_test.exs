defmodule DawarichWeb.LocaleTest do
  use ExUnit.Case, async: true

  alias Dawarich.Accounts.User
  alias DawarichWeb.Locale

  test "the parameter, then the user's own choice, then the Rails session, then English" do
    user = %User{settings: %{"locale" => " DE "}}

    assert Locale.resolve("fr", user, %{"locale" => "es"}) == "fr"
    assert Locale.resolve("xx", user, %{"locale" => "es"}) == "de"
    assert Locale.resolve(nil, %User{settings: []}, %{"locale" => "es"}) == "es"
    assert Locale.resolve(nil, nil, %{}) == "en"
  end

  test "suggests the browser's best supported language only when nobody chose one" do
    assert Locale.suggest("pl;q=0.5, de-DE;q=0.9, fr;q=0.9", nil, nil, %{}, "en") == "de"
    assert Locale.suggest("de", nil, nil, %{}, "de") == nil
    assert Locale.suggest("de", "fr", nil, %{}, "fr") == nil
    assert Locale.suggest("de", nil, %User{settings: %{"locale" => "fr"}}, %{}, "fr") == nil
    assert Locale.suggest("de", nil, nil, %{"locale" => "fr"}, "fr") == nil
    assert Locale.suggest("xx, de;q=0", nil, nil, %{}, "en") == nil
  end

  test "matches Rails quality parsing for malformed and nonstandard parameters" do
    assert Locale.suggest("de;unexpected, fr;q=0.5", nil, nil, %{}, "en") == "de"
    assert Locale.suggest("de;q=abc, fr;q=0.5", nil, nil, %{}, "en") == "fr"
    assert Locale.suggest("de;q=, fr;q=0.5", nil, nil, %{}, "en") == "fr"
    assert Locale.suggest("de;q=2, fr;q=0.5", nil, nil, %{}, "en") == "de"
    assert Locale.suggest("de;q=0.5abc, fr;q=0.6", nil, nil, %{}, "en") == "fr"
    assert Locale.suggest("de;q=1e1, fr;q=0.5", nil, nil, %{}, "en") == "de"
  end

  test "matches Ruby String.to_f for q-values" do
    expectations = [
      {".5", 0.5},
      {"5.", 5.0},
      {"0.5", 0.5},
      {"1", 1.0},
      {"2", 2.0},
      {"1e1", 10.0},
      {"1e", 1.0},
      {"1e+1", 10.0},
      {"-1", -1.0},
      {"+1", 1.0},
      {"0x10", 0.0},
      {"1_000", 1000.0},
      {"1__0", 1.0},
      {"_1", 0.0},
      {"0.5abc", 0.5},
      {"abc", 0.0},
      {"", 0.0},
      {" 0.5", 0.5},
      {"\t1", 1.0},
      {"0.5 ", 0.5},
      {"1.2.3", 1.2},
      {"Infinity", 0.0},
      {"NaN", 0.0},
      {".e1", 0.0},
      {"1.e1", 10.0}
    ]

    for {value, expected} <- expectations do
      assert Locale.ruby_to_f(value) == expected
    end
  end

  test "prefers leading-dot q-values like Rails" do
    assert Locale.suggest("de;q=.5, fr;q=0.4", nil, nil, %{}, "en") == "de"
    assert Locale.suggest("fr;q=.5, de;q=0.4", nil, nil, %{}, "en") == "fr"
  end

  test "parses case-insensitive language tags with surrounding whitespace" do
    assert Locale.suggest(" DE-de ; Q=0.9 , fr;q=0.8", nil, nil, %{}, "en") == "de"
  end

  test "self-hosted mode follows Rails' SELF_HOSTED parsing" do
    for value <- [nil, "true", " 1 ", "\"Yes\"", "on", "T"],
        do:
          assert(
            DawarichWeb.LayoutAssigns.self_hosted?(
              %{"SELF_HOSTED" => value}
              |> Map.reject(fn {_, v} -> is_nil(v) end)
            )
          )

    for value <- ["false", "0", "no", ""],
        do: refute(DawarichWeb.LayoutAssigns.self_hosted?(%{"SELF_HOSTED" => value}))
  end
end
