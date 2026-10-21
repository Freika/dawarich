defmodule Dawarich.Auth.Recovery.Messages do
  @moduledoc false
  def error(view, error, locale) do
    messages = error |> kinds() |> Enum.map(&message(view, &1, locale))

    resource =
      case Dawarich.I18n.t(locale, "activerecord.models.user", %{"count" => 1}) do
        {:ok, value} when is_binary(value) -> String.downcase(value)
        _ -> "user"
      end

    {:ok, heading} =
      Dawarich.I18n.t(locale, "errors.messages.not_saved", %{
        "count" => length(messages),
        "resource" => resource
      })

    %{heading: heading, messages: messages}
  end

  def attributes(nil), do: []

  def attributes(error) do
    for kind <- kinds(error) do
      {attribute, _kind, _bindings} = fields(:password_edit, kind, "en")
      attribute
    end
  end

  defp kinds({:validation, kinds}), do: Enum.map(kinds, &{:validation, &1})
  defp kinds(error), do: [error]

  defp message(view, error, locale) do
    {attribute, kind, bindings} = fields(view, error, locale)
    {:ok, message} = Dawarich.I18n.t(locale, "errors.messages.#{kind}", bindings)

    {:ok, full} =
      Dawarich.I18n.t(locale, "errors.format", %{
        "attribute" => attribute(locale, attribute),
        "message" => message
      })

    full
  end

  defp fields(view, :invalid, _), do: {token_attribute(view), :invalid, %{}}
  defp fields(view, :blank_token, _), do: {token_attribute(view), :blank, %{}}
  defp fields(view, :expired, _), do: {token_attribute(view), :expired, %{}}

  defp fields(_, {:validation, :confirmation}, locale),
    do: {"password_confirmation", :confirmation, %{"attribute" => attribute(locale, "password")}}

  defp fields(_, {:validation, :too_short}, _), do: {"password", :too_short, %{"count" => 12}}
  defp fields(_, {:validation, :too_long}, _), do: {"password", :too_long, %{"count" => 128}}
  defp fields(_, {:validation, :blank}, _), do: {"password", :blank, %{}}
  defp token_attribute(:unlock_new), do: "unlock_token"
  defp token_attribute(_), do: "reset_password_token"

  defp attribute(locale, key) do
    case Dawarich.I18n.t(locale, "activerecord.attributes.user." <> key) do
      {:ok, value} when is_binary(value) -> value
      _ -> key |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
