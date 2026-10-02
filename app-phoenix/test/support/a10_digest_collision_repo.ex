defmodule Dawarich.Test.A10DigestCollisionRepo do
  @moduledoc false
  def in_transaction?, do: Dawarich.Repo.in_transaction?()

  def query!(sql, params, opts \\ []) do
    if String.starts_with?(sql, "INSERT INTO digests(") and
         not Process.get(:a10_digest_collision, false) do
      Process.put(:a10_digest_collision, true)
      # A committed contender is simulated on the same owned connection before
      # the original insert. The failure is from the real packaged unique index.
      Dawarich.Repo.query!(sql, params, log: false)
    end

    Dawarich.Repo.query!(sql, params, opts)
  end
end
