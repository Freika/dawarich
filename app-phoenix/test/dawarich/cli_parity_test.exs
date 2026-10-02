defmodule Dawarich.CLIParityTest do
  use Dawarich.JobsCase

  alias Dawarich.A12eCorpus

  @external_resource A12eCorpus.path()
  @ported ~w(users_activate users_activate_cloud users_admin_recipe users_email_recipe users_password_recipe)

  for c <- A12eCorpus.cases(), c["name"] in @ported do
    @case c
    test "#{c["name"]} prints, returns and stores what Rails did" do
      result = A12eCorpus.replay(@case)
      if @case["stdout"], do: assert(result.stdout == A12eCorpus.expected_stdout(@case))
      if @case["stderr"], do: assert(A12eCorpus.stderr_message(result.stderr) == @case["stderr"])
      assert result.exit == @case["exit"]
      assert result.checks == A12eCorpus.expected_checks(@case)
    end
  end
end
