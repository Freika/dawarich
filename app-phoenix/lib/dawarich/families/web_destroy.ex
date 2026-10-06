defmodule Dawarich.Families.WebDestroy do
  @moduledoc false
  alias Dawarich.Families.{WebCreate, WebMemberships}

  def run(repo, user, ctx, opts \\ []) do
    case WebCreate.family(repo, user.id) do
      nil -> {:error, :not_in_family}
      %{role: role} when role != 0 -> {:error, :not_authorized}
      family -> destroy(repo, family, ctx, opts)
    end
  end

  defp destroy(repo, family, ctx, opts) do
    {:ok, result} =
      repo.transaction(fn ->
        repo.query!("SELECT id FROM families WHERE id=$1 FOR UPDATE", [family.id], log: false)

        [[count]] =
          repo.query!("SELECT count(*) FROM family_memberships WHERE family_id=$1", [family.id],
            log: false
          ).rows

        if count > 1 do
          {:refused, :members_present}
        else
          for [id, user, role, settings, source] <-
                repo.query!(
                  "SELECT m.id,m.user_id,m.role,u.settings,u.subscription_source FROM family_memberships m " <>
                    "JOIN users u ON u.id=m.user_id WHERE m.family_id=$1",
                  [family.id],
                  log: false
                ).rows do
            WebMemberships.delete!(repo, id, user, role, settings, source, ctx)
          end

          repo.query!("DELETE FROM family_invitations WHERE family_id=$1", [family.id],
            log: false
          )

          repo.query!("DELETE FROM family_location_requests WHERE family_id=$1", [family.id],
            log: false
          )

          repo.query!("DELETE FROM families WHERE id=$1", [family.id], log: false)
          {:ok, family.id}
        end
      end)

    if match?({:ok, _}, result), do: publish(result, opts), else: result
  end

  defp publish({:ok, id} = result, opts) do
    Keyword.get(opts, :publish, fn _ -> :ok end).(id)
    result
  rescue
    _error -> {:error, :publication_failed}
  end
end
