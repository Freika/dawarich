defmodule Dawarich.Auth.Mobile.Registration do
  @moduledoc false
  alias Dawarich.Auth.{Registration, RegistrationPolicy}
  alias Dawarich.Auth.Mobile.Payload
  alias DawarichWeb.Translate

  def create(params, context) do
    context = RegistrationPolicy.context(context)
    invitation = RegistrationPolicy.invitation(params["invitation_token"], context)

    context =
      context |> Map.put(:invitation, invitation) |> Map.put(:registration_channel, :mobile)

    case Registration.register(params, %{}, context) do
      {:ok, result} ->
        Payload.success(result.user, true, context)

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

      {:error, _reason} ->
        {:error, 503, %{"error" => "authentication_unavailable"}}
    end
  end
end
