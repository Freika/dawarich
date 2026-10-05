defmodule Dawarich.Mail.Digests.ChartsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Mail.Digests.Charts

  @path Path.expand("../../../fixtures/mail/residual/digest_content.json", __DIR__)
  @ids ~w(hbar_empty hbar_zero hbar_half hbar_negative hbar_all_negative spark_empty
          spark_equal spark_negative_half heatmap_empty heatmap_quartiles heatmap_sparse_negative
          ranked_empty ranked_unicode_ties ranked_negative trend_equal trend_prior_zero
          trend_negative_half trend_positive_half trend_pct_nil trend_pct_minus100_zero
          trend_pct_minus100_positive)
  @methods %{
    "ascii_hbar" => :hbar,
    "ascii_sparkline" => :sparkline,
    "ascii_year_heatmap" => :year_heatmap,
    "ascii_ranked_list" => :ranked_list,
    "ascii_trend" => :trend,
    "ascii_trend_from_pct" => :trend_from_pct
  }
  @options %{
    "labels" => :labels,
    "width" => :width,
    "suffix" => :suffix,
    "start_date" => :start_date,
    "value_key" => :value_key,
    "label_key" => :label_key
  }

  test "ASCII digest helpers match Rails boundaries padding and rounding" do
    helpers = @path |> File.read!() |> Jason.decode!() |> Map.fetch!("helpers")
    assert Enum.map(helpers, & &1["id"]) == @ids

    for row <- helpers do
      {args, opts} = arguments(row)
      render = fn -> apply(Charts, Map.fetch!(@methods, row["method"]), args ++ [opts]) end

      if row["error"] do
        assert row["error"] == "ArgumentError", row["id"]
        assert_raise ArgumentError, render
      else
        if render.() != row["output"], do: flunk("chart differs: " <> row["id"])
      end
    end
  end

  defp arguments(row) do
    opts =
      Enum.map(row["kwargs"], fn {key, value} ->
        value = if key == "start_date", do: Date.from_iso8601!(value), else: value
        {Map.fetch!(@options, key), value}
      end)

    args =
      if row["method"] == "ascii_year_heatmap" do
        [Map.new(hd(row["args"]), fn {date, value} -> {Date.from_iso8601!(date), value} end)]
      else
        row["args"]
      end

    {args, opts}
  end
end
