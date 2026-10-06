defmodule Dawarich.Auth.Mobile.Registration do
  @moduledoc false
  alias Dawarich.Auth.{Account, Registration, RegistrationPolicy, RegistrationSetup}
  alias Dawarich.Auth.Mobile.Payload
  alias DawarichWeb.Translate

  def create(params, context) do
    context = RegistrationPolicy.context(context)
    invitation = RegistrationPolicy.invitation(params["invitation_token"], context)
    context = Map.put(context, :invitation, invitation)

    case Registration.create(params, context) do
      {:ok, user} ->
        finish(user, params, context)

      {:error, :denied} ->
        key = RegistrationPolicy.denial_key(context, invitation, params["email"])

        {:error, 403,
         %{
           "error" => "registration_disabled",
           "message" => Translate.t(Map.get(context, :locale, "en"), key, %{})
         }}

      {:error, %{errors: errors}} ->
        details =
          Enum.reduce(errors, %{}, fn {field, type, bindings}, acc ->
            bindings =
              if type == :confirmation,
                do: Map.put(bindings, "attribute", "Password"),
                else: bindings

            key = "errors.messages." <> Atom.to_string(type)
            text = Translate.t(Map.get(context, :locale, "en"), key, bindings)
            Map.update(acc, Atom.to_string(field), [text], &(&1 ++ [text]))
          end)

        {:error, 422, %{"error" => "validation_failed", "details" => details}}
    end
  end

  defp finish(user, _params, %{self_hosted: false} = context) do
    callback = get_in(context, [:callbacks, :webhook])

    if not is_function(callback, 1) or callback.(user.id) != :ok,
      do: raise("Signup callback unavailable")

    invitation = context[:invitation]

    accepted =
      if invitation && invitation.acceptable &&
           Account.normalize_email(invitation.email) == user.email do
        callback = get_in(context, [:callbacks, :accept_invitation])

        if not is_function(callback, 2) or callback.(user.id, invitation.id) != :ok,
          do: raise("Family callback unavailable")

        true
      else
        false
      end

    repo = Map.get(context, :repo, Dawarich.Repo)

    user =
      if accepted,
        do: repo.get!(Account, user.id),
        else: repo.update!(Ecto.Changeset.change(user, status: 3), log: false)

    Payload.success(user, true, context)
  end

  defp finish(user, params, context) do
    {:ok, result} = RegistrationSetup.complete(user, params, %{}, context)
    Payload.success(result.user, true, context)
  end
end
