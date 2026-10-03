defmodule Dawarich.Auth.AccountValidation do
  @moduledoc false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.I18n

  def validate(params, current_email, opts \\ []) do
    email = Account.normalize_email(Map.get(params, "email", current_email))
    password = Map.get(params, "password")
    confirmation = Map.get(params, "password_confirmation")

    confirmation =
      if Token.blank?(password) and Token.blank?(confirmation), do: nil, else: confirmation

    password = if Token.blank?(password), do: nil, else: password
    locale = Keyword.get(opts, :locale, "en")

    errors =
      email_errors(email, current_email, opts) ++
        password_errors(password, confirmation) ++ current_password_errors(params, opts)

    changes = if email == current_email, do: %{}, else: %{email: email}
    changes = if is_nil(password), do: changes, else: Map.put(changes, :password, password)

    %{
      changes: changes,
      errors: errors,
      render: %{email: email, errors: errors, messages: messages(errors, locale)}
    }
  end

  def messages(errors, locale) do
    Enum.map(errors, fn {field, kind, bindings} ->
      bindings =
        if kind == :confirmation,
          do: Map.put(bindings, "attribute", attribute(locale, :password)),
          else: bindings

      {:ok, message} = I18n.t(locale, "errors.messages.#{kind}", bindings)

      {:ok, full} =
        I18n.t(locale, "errors.format", %{
          "attribute" => attribute(locale, field),
          "message" => message
        })

      full
    end)
  end

  defp email_errors(email, current, opts) do
    cond do
      Token.blank?(email) ->
        [{:email, :blank, %{}}]

      email == current ->
        []

      true ->
        add([], Keyword.get(opts, :email_taken, false), :email, :taken) ++
          add([], not Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/u, email), :email, :invalid)
    end
  end

  defp password_errors(password, confirmation) do
    required = not is_nil(password) or not is_nil(confirmation)
    length = if is_nil(password), do: 0, else: length(String.codepoints(password))

    []
    |> add(required and is_nil(password), :password, :blank)
    |> add(
      not is_nil(confirmation) and confirmation != password,
      :password_confirmation,
      :confirmation
    )
    |> add(not is_nil(password) and length < 12, :password, :too_short, %{"count" => 12})
    |> add(not is_nil(password) and length > 128, :password, :too_long, %{"count" => 128})
  end

  defp current_password_errors(params, opts) do
    if Keyword.get(opts, :current_password_valid, false) do
      []
    else
      kind = if Token.blank?(params["current_password"]), do: :blank, else: :invalid
      [{:current_password, kind, %{}}]
    end
  end

  defp add(errors, failed, field, kind, bindings \\ %{})
  defp add(errors, true, field, kind, bindings), do: errors ++ [{field, kind, bindings}]
  defp add(errors, false, _, _, _), do: errors

  defp attribute(locale, field) do
    case I18n.t(locale, "activerecord.attributes.user.#{field}") do
      {:ok, value} when is_binary(value) -> value
      _ -> field |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
    end
  end
end
