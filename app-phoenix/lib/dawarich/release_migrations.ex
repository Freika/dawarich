defmodule Dawarich.ReleaseMigrations do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.{
    Unreleased,
    V1_4_0,
    V1_5_0,
    V1_6_0,
    V1_7_0,
    V1_7_1,
    V1_7_2,
    V1_7_5,
    V1_7_6,
    V1_7_7,
    V1_7_8,
    V1_7_11,
    V1_8_0,
    V1_8_1,
    V1_9_0,
    V1_9_1,
    V1_10_0,
    V1_10_1,
    V1_10_2,
    V1_11_0,
    V1_12_0,
    V1_12_2,
    V1_13_0,
    V1_13_1,
    V1_14_0,
    V1_14_1,
    V1_14_2,
    V1_14_3,
    V1_14_4,
    V1_15_0,
    V1_15_2
  }

  @releases [
    V1_4_0,
    V1_5_0,
    V1_6_0,
    V1_7_0,
    V1_7_1,
    V1_7_2,
    V1_7_5,
    V1_7_6,
    V1_7_7,
    V1_7_8,
    V1_7_11,
    V1_8_0,
    V1_8_1,
    V1_9_0,
    V1_9_1,
    V1_10_0,
    V1_10_1,
    V1_10_2,
    V1_11_0,
    V1_12_0,
    V1_12_2,
    V1_13_0,
    V1_13_1,
    V1_14_0,
    V1_14_1,
    V1_14_2,
    V1_14_3,
    V1_14_4,
    V1_15_0,
    V1_15_2,
    Unreleased
  ]

  def all, do: @releases

  def find(release), do: Enum.find(@releases, &(&1.release() == release))
end
