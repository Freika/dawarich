defmodule DawarichWeb.NativeMapFamilyLabelsTest do
  use ExUnit.Case, async: true

  test "native Family layer keeps localized singular and plural sharing date labels" do
    for locale <- Dawarich.I18n.available_locales() do
      labels = DawarichWeb.NativeMapLabels.labels(locale)
      assert is_binary(labels["family.sharing_since.one"])
      assert labels["family.sharing_since.one"] =~ "{date}"
      assert labels["family.sharing_since.other"] =~ "{date}"
      assert labels["family.sharing_since.other"] =~ "{count}"
    end

    labels = DawarichWeb.NativeMapLabels.labels("en")
    assert labels["family.sharing_since.one"] == "Sharing since {date} (1 day of history)"

    assert labels["family.sharing_since.other"] ==
             "Sharing since {date} ({count} days of history)"
  end

  test "native Family layer keeps localized loaded member count labels" do
    for locale <- Dawarich.I18n.available_locales() do
      labels = DawarichWeb.NativeMapLabels.labels(locale)
      assert is_binary(labels["family.loaded_members.one"])
      assert labels["family.loaded_members.other"] =~ "{count}"
    end

    labels = DawarichWeb.NativeMapLabels.labels("en")
    assert labels["family.loaded_members.one"] == "Loaded 1 family member"
    assert labels["family.loaded_members.other"] == "Loaded {count} family members"
  end
end
