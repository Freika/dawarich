defmodule DawarichWeb.SegmentLegs do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.{Icon, SegmentFormat, TimelineFormat}
  alias Phoenix.LiveView.JS
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat, as: FloatText

  attr :display, :map, required: true
  attr :track_id, :integer, required: true
  attr :user, :map, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :unit, :string, required: true
  attr :native, :boolean, default: false

  def legs(assigns) do
    ~H"""
    <div id={"track-#{@track_id}-legs"} class="segment-legs" data-testid={"track-legs-#{@track_id}"}>
      <div class="segment-ribbon" aria-hidden="true">
        <%= for span <- @display.spans do %>
          <%= case span.kind do %>
            <% :mode -> %>
              <i style={"width: #{FloatText.to_s(span.percent)}%; background: #{color(span.mode)}"}></i>
            <% :uncertain -> %>
              <i class="segment-ribbon__uncertain" style={"width: #{FloatText.to_s(span.percent)}%"}></i>
            <% _ -> %>
              <i class="segment-ribbon__gap" style={"width: #{FloatText.to_s(span.percent)}%"}></i>
          <% end %>
        <% end %>
      </div>
      <%= for item <- @display.items do %>
        <%= case item.kind do %>
          <% :stop -> %>
            <div class="segment-stop">
              {s(@locale, "stop_duration", %{
                duration: TimelineFormat.duration_short(@locale, item.duration)
              })}
            </div>
          <% :transfer -> %>
            <div
              class="segment-leg segment-leg--neutral"
              title={s(@locale, "short_segments", %{count: item.segment_count})}
            >
              <Icon.icon name="line-squiggle" class="segment-leg__icon" />
              <span class="segment-leg__mode">{s(@locale, "transfer")}</span>
              <.numbers item={item} locale={@locale} unit={@unit} />
            </div>
          <% _ -> %>
            <div
              class={
                if item.kind == :uncertain,
                  do: "segment-leg segment-leg--neutral",
                  else: "segment-leg"
              }
              title={if item.kind == :uncertain, do: s(@locale, "mode_unclear")}
              data-controller={!@native && "segment-mode-editor"}
              data-segment-mode-editor-segment-id-value={!@native && (item.segment_id || "")}
              data-segment-mode-editor-track-id-value={!@native && @track_id}
              data-segment-mode-editor-mode-value={!@native && (item.mode || "unknown")}
              data-action={
                !@native &&
                  "mouseenter->segment-mode-editor#hover mouseleave->segment-mode-editor#unhover"
              }
              data-native-segment-id={@native && item.segment_id}
              data-native-track-id={@native && @track_id}
            >
              <Icon.icon
                name={
                  if item.kind == :uncertain,
                    do: "line-squiggle",
                    else: TimelineFormat.mode_icon(item.mode)
                }
                class="segment-leg__icon"
              />
              <.mode
                track_id={@track_id}
                segment_id={item.segment_id}
                mode={item.mode || "unknown"}
                label={
                  if item.kind == :uncertain,
                    do: s(@locale, "moving"),
                    else: t(@locale, "transportation_modes.#{item.mode}", %{})
                }
                user={@user}
                locale={@locale}
                csrf={@csrf}
                native={@native}
              />
              <.numbers item={item} locale={@locale} unit={@unit} />
            </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp mode(assigns) do
    ~H"""
    <form
      id={@native && "native-leg-form-#{@segment_id}"}
      class="segment-leg__form"
      action={"/tracks/#{@track_id}/segments/#{@segment_id}"}
      accept-charset="UTF-8"
      method="post"
      phx-change={@native && JS.push("segment:mode", value: %{segment_id: @segment_id})}
      phx-auto-recover={@native && "ignore"}
    >
      <input type="hidden" name="_method" value="patch" />
      <input type="hidden" name="authenticity_token" value={@csrf} />
      <label class="segment-leg__mode segment-leg__mode--editable">
        <span>{@label}</span>
        <Icon.icon name="chevron-down" class="segment-leg__caret" />
        <select
          class="segment-leg__select"
          aria-label={
            t(@locale, "tracks.segments.segment_row.transportation_mode_currently", %{mode: @label})
          }
          data-action={!@native && "change->segment-mode-editor#submit"}
          data-testid={"leg-mode-select-#{@segment_id}"}
          name="track_segment[transportation_mode]"
          id={
            if @native,
              do: "native-leg-mode-#{@segment_id}",
              else: "track_segment_transportation_mode"
          }
        >
          <option
            :for={{label, value} <- SegmentFormat.modes_for_mode(@mode, @user, @locale)}
            selected={if value == @mode, do: "selected"}
            value={value}
          >
            {label}
          </option>
        </select>
      </label>
    </form>
    """
  end

  defp numbers(assigns) do
    ~H"""
    <span class="segment-leg__nums" phx-no-format><span class="segment-leg__mid" aria-hidden="true">·</span>{SegmentFormat.segment_distance(@item.distance, @unit, @locale)}<span class="segment-leg__mid" aria-hidden="true">·</span>{TimelineFormat.duration_short(@locale, @item.duration)}</span>
    """
  end

  defp color(mode),
    do: mode |> Dawarich.Transportation.Segments.mode_to_int() |> Dawarich.MapApi.Segments.color()

  defp s(locale, key, bindings \\ %{}), do: t(locale, "tracks.segments.legs." <> key, bindings)
end
