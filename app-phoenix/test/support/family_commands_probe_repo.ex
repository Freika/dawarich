defmodule Dawarich.Test.FamilyCommandsProbeRepo do
  alias Dawarich.ScratchRepo

  defdelegate transaction(fun), to: ScratchRepo
  defdelegate rollback(reason), to: ScratchRepo
  defdelegate in_transaction?(), to: ScratchRepo
  defdelegate get(schema, id, opts), to: ScratchRepo
  defdelegate query(sql, params), to: ScratchRepo
  defdelegate insert!(changeset, opts), to: ScratchRepo

  def query!(sql, params, opts \\ []) do
    if String.starts_with?(sql, "SELECT id FROM families WHERE id=$1") do
      if parent = Process.delete(:family_command_waiter) do
        [[pid]] = ScratchRepo.query!("SELECT pg_backend_pid()", [], log: false).rows
        send(parent, {:family_waiter, pid})
      end
    end

    result = ScratchRepo.query!(sql, params, opts)

    if String.starts_with?(sql, "SELECT id FROM families WHERE id=$1") do
      if parent = Process.delete(:family_recheck_probe) do
        send(parent, {:family_locked, self()})

        receive do
          :release_family -> :ok
        after
          5000 -> raise "family probe release timeout"
        end
      end
    end

    if String.starts_with?(sql, [
         "SELECT target_user_id,status,expires_at FROM family_location_requests",
         "SELECT id,family_id,email,status,expires_at FROM family_invitations"
       ]) do
      if parent = Process.delete(:family_row_probe) do
        send(parent, {:family_locked, self()})

        receive do
          :release_family -> :ok
        after
          5000 -> raise "row probe release timeout"
        end
      end
    end

    if String.starts_with?(sql, "SELECT (SELECT count(*) FROM family_memberships") do
      if parent = Process.delete(:family_command_probe) do
        send(parent, {:capacity_checked, self()})

        receive do
          :release_family -> :ok
        after
          5000 -> raise "capacity probe release timeout"
        end
      end
    end

    result
  end
end
