defmodule Dawarich.Admin.UserValidation do
  @moduledoc false
  alias Dawarich.Auth.AccountValidation
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.I18n

  @statuses %{"inactive" => 0, "active" => 1, "trial" => 2, "pending_payment" => 3}

  def create(params, context \\ %{}) do
    params = Map.take(params, ~w(email password)) |> Map.put_new("email", "")
    params = Map.update!(params, "email", &(&1 || ""))
    params = Map.put(params, "password_confirmation", params["password"])
    result = AccountValidation.validate(params, nil, validation_options(context))

    errors =
      if Token.blank?(params["password"]),
        do: result.errors ++ [{:password, :blank, %{}}],
        else: result.errors

    result(result.changes, errors, :create, context)
  end

  def update(target, params, context \\ %{}) do
    params = Map.take(params, ~w(email password admin status))

    params =
      if Map.has_key?(params, "email"),
        do: Map.update!(params, "email", &(&1 || "")),
        else: params

    validation = AccountValidation.validate(params, target.email, validation_options(context))

    with {:ok, roles} <- roles(params) do
      roles = Map.reject(roles, fn {key, value} -> Map.get(target, key) == value end)
      result(Map.merge(validation.changes, roles), validation.errors, :update, context)
    end
  end

  defp validation_options(context) do
    [
      current_password_valid: true,
      email_taken: Map.get(context, :email_taken, false),
      locale: Map.get(context, :locale, "en")
    ]
  end

  defp result(changes, [], _action, _context), do: {:ok, changes}

  defp result(_changes, errors, action, context) do
    locale = Map.get(context, :locale, "en")
    messages = AccountValidation.messages(errors, locale)

    key =
      if action == :create,
        do: "user_could_not_be_created_to_sentence",
        else: "user_could_not_be_updated_to_sentence"

    {:ok, message} =
      I18n.t(locale, "controllers.settings.users." <> key, %{
        "errors" => sentence(messages, locale)
      })

    {:invalid, message}
  end

  defp sentence([message], _locale), do: message

  defp sentence([first, last], locale),
    do: first <> connector(locale, "two_words_connector") <> last

  defp sentence(messages, locale) do
    {last, rest} = List.pop_at(messages, -1)

    Enum.join(rest, connector(locale, "words_connector")) <>
      connector(locale, "last_word_connector") <> last
  end

  defp connector(locale, key) do
    {:ok, value} = I18n.t(locale, "support.array." <> key)
    value
  end

  defp roles(params) do
    changes =
      if Map.has_key?(params, "admin"),
        do: %{admin: Dawarich.UserSettings.cast(params["admin"])},
        else: %{}

    if Map.has_key?(params, "status") do
      case status(params["status"]) do
        {:ok, value} -> {:ok, Map.put(changes, :status, value)}
        _ -> {:handoff, :invalid_status}
      end
    else
      {:ok, changes}
    end
  end

  defp status(value) when value in [nil, ""], do: {:ok, nil}
  defp status(value) when is_integer(value) and value in 0..3, do: {:ok, value}
  defp status(value), do: Map.fetch(@statuses, value)
end
