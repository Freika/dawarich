defmodule Dawarich.Auth.RegistrationCallbacks do
  @moduledoc false
  alias Dawarich.{AfterCommit, Repo}
  alias Dawarich.Auth.Account
  alias Dawarich.Users.WebhookCommands

  def context(context) do
    repo = Map.get(context, :repo, Repo)
    callbacks = Map.get(context, :callbacks, %{}) || %{}

    callbacks =
      callbacks
      |> Map.put_new(:webhook, fn id ->
        WebhookCommands.creation(repo, id, AfterCommit.identity(id, "users.creation_webhook"))
      end)
      |> Map.put_new(:partnero, fn id, partner ->
        Dawarich.Partnero.CustomerSignup.enqueue(
          repo,
          id,
          partner,
          AfterCommit.identity(id, "partnero.customer_signup")
        )
      end)
      |> Map.put_new(:accept_invitation, fn id, invitation ->
        accept(repo, id, invitation, context)
      end)

    Map.put(context, :callbacks, callbacks)
  end

  def creation_options(context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)

    env =
      Map.put(env, "SELF_HOSTED", if(context[:self_hosted] == false, do: "false", else: "true"))

    [
      env: env,
      now: Map.get(context, :clock, &DateTime.utc_now/0).(),
      locale: Map.get(context, :locale, "en"),
      skip_auto_trial: context[:self_hosted] == false,
      webhook: get_in(context, [:callbacks, :webhook])
    ]
  end

  defp accept(repo, id, invitation, context) do
    case repo.query!("SELECT token FROM family_invitations WHERE id=$1", [invitation], log: false).rows do
      [[token]] ->
        user = repo.get!(Account, id, log: false)

        ctx = %{
          self_hosted: false,
          now: Map.get(context, :clock, &DateTime.utc_now/0).(),
          locale: Map.get(context, :locale, "en")
        }

        case Dawarich.Families.WebInvitations.accept(repo, user, token, ctx) do
          {:ok, _} -> :ok
          {:error, reason} when reason in [:family_lapsed, :family_full] -> {:refused, reason}
          error -> error
        end

      [] ->
        {:error, :not_found}
    end
  end
end
