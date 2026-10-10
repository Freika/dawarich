defmodule Dawarich.WebValidation do
  @moduledoc false
  alias Dawarich.I18n

  @notes %{
    "Body can't be blank" => {"body", "errors.messages.blank", %{}},
    "Body is too long (maximum is 10000 characters)" =>
      {"body", "errors.messages.too_long", %{"count" => 10_000}},
    "Noted at can't be blank" => {"noted_at", "errors.messages.blank", %{}},
    "Attachable type is not included in the list" =>
      {"attachable_type", "errors.messages.inclusion", %{}},
    "Attachable can't be blank" => {"attachable", "errors.messages.blank", %{}},
    "Date has already been taken" => {"date", "models.note.has_already_been_taken", %{}},
    "Date must be within the trip date range" =>
      {"date", "models.note.must_be_within_the_trip_date_range", %{}},
    "Attachable must belong to the same user" =>
      {"attachable", "models.note.must_belong_to_the_same_user", %{}}
  }

  def message(locale, model, field, key, bindings \\ %{}) do
    attribute =
      Enum.find_value(
        ["activerecord.attributes.#{model}.#{field}", "attributes.#{field}"],
        fn key ->
          case I18n.t(locale, key) do
            {:ok, text} when is_binary(text) -> text
            _ -> nil
          end
        end
      ) || field |> String.replace("_", " ") |> String.capitalize()

    {:ok, text} = I18n.t(locale, key, bindings)
    {:ok, full} = I18n.t(locale, "errors.format", %{"attribute" => attribute, "message" => text})
    full
  end

  def notes("en", errors), do: {:ok, errors}

  def notes(locale, errors) do
    Enum.reduce_while(errors, {:ok, []}, fn error, {:ok, translated} ->
      case @notes[error] do
        {field, key, bindings} ->
          {:cont, {:ok, translated ++ [message(locale, "note", field, key, bindings)]}}

        nil ->
          {:halt, {:replay, "unsupported localized note validation"}}
      end
    end)
  end
end
