defmodule Dawarich.I18nTest do
  use ExUnit.Case, async: true

  alias Dawarich.I18n
  alias DawarichWeb.Translate

  @tree %{
    "en" => %{
      "a" => %{
        "greet" => "Hello %{name}",
        "days" => %{"zero" => "none", "one" => "%{count} day", "other" => "%{count} days"},
        "only_en" => "English",
        "percent" => "100%% of %{name}",
        "list" => ["x", "y"],
        "greetings" => ["Hi %{name}", "Bye %{name}"],
        "reserved" => "Value %{format}"
      }
    },
    "de" => %{
      "a" => %{
        "greet" => "Hallo %{name}",
        "days" => %{"one" => "%{count} Tag", "other" => "%{count} Tage"}
      }
    }
  }

  test "looks a dotted key up in the locale and interpolates" do
    assert I18n.lookup(@tree, "de", "a.greet", %{"name" => "Eugen"}) == {:ok, "Hallo Eugen"}
  end

  test "falls back to English, unless told not to" do
    assert I18n.lookup(@tree, "de", "a.only_en", %{}) == {:ok, "English"}
    assert I18n.lookup(@tree, "de", "a.only_en", %{}, fallback: false) == :missing
    assert I18n.lookup(@tree, "de", "a.nowhere", %{}) == :missing
  end

  test "pluralizes like Rails' simple backend" do
    assert I18n.lookup(@tree, "en", "a.days", %{"count" => 0}) == {:ok, "none"}
    assert I18n.lookup(@tree, "de", "a.days", %{"count" => 0}) == {:ok, "0 Tage"}
    assert I18n.lookup(@tree, "de", "a.days", %{"count" => 1}) == {:ok, "1 Tag"}
    assert I18n.lookup(@tree, "de", "a.days", %{"count" => 21}) == {:ok, "21 Tage"}
  end

  test "a missing argument is an error and %% is a literal percent sign" do
    assert I18n.lookup(@tree, "en", "a.greet", %{}) == {:error, {:missing_interpolation, "name"}}
    assert I18n.lookup(@tree, "en", "a.percent", %{"name" => "it"}) == {:ok, "100% of it"}
    assert I18n.lookup(@tree, "en", "a.list", %{}) == {:ok, ["x", "y"]}
  end

  test "resolves a stringified count to Rails' :other, never :zero/:one, and never the raw hash" do
    assert I18n.lookup(@tree, "en", "a.days", %{"count" => "0"}) == {:ok, "0 days"}
    assert I18n.lookup(@tree, "en", "a.days", %{"count" => "1"}) == {:ok, "1 days"}
  end

  test "interpolate recurses into array values like Rails' Base#interpolate" do
    assert I18n.lookup(@tree, "en", "a.greetings", %{"name" => "Eugen"}) ==
             {:ok, ["Hi Eugen", "Bye Eugen"]}
  end

  test "a reserved interpolation key is refused like Rails' ReservedInterpolationKey" do
    assert I18n.lookup(@tree, "en", "a.reserved", %{"format" => "CSV"}) ==
             {:error, {:reserved_interpolation_key, "format"}}
  end

  test "reads the tree Rails exported, gem locale files included" do
    export = export()

    assert I18n.t("de", "shared.navbar.logout") ==
             {:ok, get_in(export, ~w(de shared navbar logout))}

    assert I18n.t("en", "datetime.distance_in_words.x_days", %{"count" => 3}) == {:ok, "3 days"}
  end

  test "the real unsupported_file_format key interpolates file_format" do
    assert I18n.t("en", "services.exports.create.unsupported_file_format", %{
             "file_format" => "CSV"
           }) == {:ok, "Unsupported file format: CSV"}
  end

  test "the reserved keys pinned from the i18n gem match the fixture Rails generated" do
    fixture = "test/fixtures/i18n_reserved_keys.json" |> File.read!() |> Jason.decode!()
    assert Enum.sort(I18n.reserved_keys()) == fixture["reserved_keys"]
  end

  test "templates get escaped text, raw _html keys with escaped arguments, and Rails' missing marker" do
    export = export()

    assert Translate.t("en", "shared.navbar.logout", %{}) ==
             get_in(export, ~w(en shared navbar logout))

    assert Translate.t("en", "family_mailer.member_joined.share_location_with_html", %{
             "email" => "<b>x</b>"
           }) ==
             {:safe, "Share your location with <strong>&lt;b&gt;x&lt;/b&gt;</strong>"}

    assert Translate.t("en", "nope.some_key", %{}) ==
             {:safe,
              ~s(<span class="translation_missing" title="translation missing: en.nope.some_key">Some Key</span>)}
  end

  test "an _html key escapes an iolist binding instead of letting markup through raw" do
    assert Translate.t("en", "family_mailer.member_joined.share_location_with_html", %{
             "email" => ["<script>alert(1)</script>"]
           }) ==
             {:safe,
              "Share your location with <strong>&lt;script&gt;alert(1)&lt;/script&gt;</strong>"}
  end

  test "an _html key escapes a nested iolist binding" do
    assert Translate.t("en", "family_mailer.member_joined.share_location_with_html", %{
             "email" => ["<a>", ["<b>", "c"]]
           }) ==
             {:safe, "Share your location with <strong>&lt;a&gt;&lt;b&gt;c</strong>"}
  end

  test "an _html key escapes an atom binding" do
    assert Translate.t("en", "family_mailer.member_joined.share_location_with_html", %{
             "email" => :"<b>"
           }) ==
             {:safe, "Share your location with <strong>&lt;b&gt;</strong>"}
  end

  test "an _html key stringifies an integer binding, which needs no escaping" do
    assert Translate.t("en", "family_mailer.member_joined.share_location_with_html", %{
             "email" => 5
           }) ==
             {:safe, "Share your location with <strong>5</strong>"}
  end

  test "an _html key passes a pre-escaped {:safe, _} binding through unescaped" do
    assert Translate.t("en", "family_mailer.member_joined.share_location_with_html", %{
             "email" => {:safe, "<b>already safe</b>"}
           }) ==
             {:safe, "Share your location with <strong><b>already safe</b></strong>"}
  end

  test "an _html key with a numeric count keeps pluralization correct instead of forcing 'other'" do
    assert Translate.t("en", "family_mailer.member_joined.member_count_html", %{"count" => 1}) ==
             {:safe, "Your family now has <strong>1</strong> member."}

    assert Translate.t("en", "family_mailer.member_joined.member_count_html", %{"count" => 3}) ==
             {:safe, "Your family now has <strong>3</strong> members."}
  end

  test "Translate.t raises ArgumentError for a reserved interpolation key from a crafted tree" do
    assert_raise ArgumentError, fn ->
      Translate.t(@tree, "en", "a.reserved", %{"format" => "CSV"})
    end
  end

  test "the missing-translation label matches ActionView's keys.last.to_s.titleize, _id suffix included" do
    cases = %{
      "thing_id" => "Thing",
      "some_key" => "Some Key",
      "_leading" => "Leading",
      "trailing_" => "Trailing ",
      "__both__" => "Both  ",
      "a_b_c_id" => "A B C",
      "id" => "Id",
      "nowhere" => "Nowhere",
      "foo-bar" => "Foo Bar",
      "thing-id" => "Thing",
      "FooBar" => "Foo Bar",
      "foo_Bar" => "Foo Bar",
      "SomeModule::SubKey" => "Some Module/Sub Key",
      "already_id" => "Already"
    }

    for {segment, label} <- cases do
      assert Translate.t("en", "nope.#{segment}", %{}) ==
               {:safe,
                ~s(<span class="translation_missing" title="translation missing: en.nope.#{segment}">#{label}</span>)}
    end
  end

  defp export,
    do: Application.fetch_env!(:dawarich, :i18n_path) |> File.read!() |> Jason.decode!()
end
