defmodule Dawarich.Digests.RefreshActivityTest do
  use ExUnit.Case, async: true
  alias Dawarich.Digests.Refresh.Activity
  @fixture Path.expand("../../fixtures/insights/activity-thresholds.json", __DIR__)

  test "gap classification equals actual source private classifier at all captured boundaries" do
    for row <- Jason.decode!(File.read!(@fixture)) do
      assert Activity.classify(row["seconds"], row["km"]) ==
               {row["result"]["stationary"], row["result"]["flying"]}
    end
  end
end
