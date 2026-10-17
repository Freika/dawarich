defmodule Dawarich.Admin.BackgroundPageTest do
  use ExUnit.Case, async: true
  alias Dawarich.Admin.BackgroundPage

  test "background projection matches SafeSettings visits values and queued GPS notice" do
    for name <-
          ~w(default string_true string_false bool_true bool_false nil queued recalculated neither) do
      state = Jason.decode!(File.read!("test/fixtures/admin_pages/background_#{name}.json"))
      user = %{settings: state["user"]["settings"], points_count: 0}
      assert BackgroundPage.read(user) == %{visits: state["visits"], notice: state["notice"]}
    end

    for blank <- [nil, false, "", " ", [], %{}] do
      settings = %{"anomaly_rules_recalculation_queued_at" => blank}
      refute BackgroundPage.read(%{settings: settings, points_count: 10}).notice

      settings = %{
        "anomaly_rules_recalculation_queued_at" => "queued",
        "anomaly_rules_recalculated_at" => blank
      }

      assert BackgroundPage.read(%{settings: settings, points_count: 0}).notice
    end
  end
end
