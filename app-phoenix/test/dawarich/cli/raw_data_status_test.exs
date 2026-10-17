defmodule Dawarich.CLI.RawDataStatusTest do
  use ExUnit.Case, async: true

  alias Dawarich.A12eCorpus
  alias Dawarich.CLI.RawDataStatus

  @external_resource A12eCorpus.path()

  test "human_size/1 is ActiveSupport's number_to_human_size for every recorded size" do
    for [bytes, rails] <- A12eCorpus.corpus()["human_sizes"],
        do: assert(RawDataStatus.human_size(bytes) == rails, "#{bytes}")
  end
end
