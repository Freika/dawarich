defmodule Dawarich.Auth.RegistrationPolicy do
  @moduledoc false
  alias Dawarich.Auth.{Account, Admission, RegistrationSetting}

  def context(opts) do
    opts
    |> Map.put_new_lazy(:self_hosted, fn -> System.get_env("SELF_HOSTED", "true") != "false" end)
    |> Map.put_new_lazy(:oidc, &Admission.oidc?/0)
    |> Map.put_new_lazy(:registration_enabled, fn ->
      case RegistrationSetting.fetch() do
        {:ok, value} -> value
        :error -> nil
      end
    end)
  end

  def allowed?(context, invitation, email) do
    cond do
      context[:self_hosted] == false -> true
      context[:oidc] == true and context[:registration_enabled] != true -> false
      context[:registration_enabled] == true -> true
      true -> matches?(invitation, email)
    end
  end

  def denial_key(context, invitation, email) do
    cond do
      context[:oidc] == true and context[:registration_enabled] != true ->
        "controllers.users.registrations.email_password_registration_is_disabled_please_use_oidc_to_sign"

      invitation && invitation.acceptable && not matches?(invitation, email) ->
        "services.families.accept_invitation.this_invitation_is_not_for_your_email_address"

      true ->
        "controllers.users.registrations.registration_is_not_available_please_contact_your_administrator_for_acce"
    end
  end

  def invitation(token, context) when is_binary(token) and token != "" do
    repo = Map.get(context, :repo, Dawarich.Repo)
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()

    case repo.query!(
           "SELECT i.id,i.email,i.family_id,i.status=0 AND i.expires_at>=$2,f.name,u.email FROM family_invitations i JOIN families f ON f.id=i.family_id JOIN users u ON u.id=i.invited_by_id WHERE i.token=$1",
           [token, now],
           log: false
         ).rows do
      [[id, email, family_id, acceptable, name, inviter]] ->
        %{
          id: id,
          email: email,
          family_id: family_id,
          acceptable: acceptable,
          name: name,
          inviter: inviter,
          token: token
        }

      [] ->
        nil
    end
  end

  def invitation(_, _), do: nil

  defp matches?(%{email: expected, acceptable: true}, email) when is_binary(email),
    do: Account.normalize_email(expected) == Account.normalize_email(email)

  defp matches?(_, _), do: false
end
