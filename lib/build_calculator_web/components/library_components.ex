defmodule BuildCalculatorWeb.LibraryComponents do
  @moduledoc """
  Rendering a *saved* build — the row, not the character.

  Everything here reads the denormalised columns
  (`BuildCalculator.Library.Build`) rather than decoding the code: a feed of
  twenty builds would otherwise inflate, unzip and parse twenty payloads to
  print two lines each. The columns exist for exactly this.

  Names follow CLAUDE.md §4: classes stay English (`Dwarven defender`), the race
  leads with Siala's own name and carries the engine's underneath —
  `Гном (Dwarf)`, and mind that `Карлик` is Gnome.

  A build saved under an older ruleset is rendered with *that* ruleset, never
  with the newest one; if the version is gone entirely we fall back to the
  default and the id shows through, which is honest about what we no longer know.
  """
  use BuildCalculatorWeb, :html

  alias BuildCalculator.Data
  alias BuildCalculator.Ids
  alias BuildCalculator.Library.Build
  alias BuildCalculatorWeb.Builder.{Labels, Palette}

  @doc "One build in a feed."
  attr :id, :string, required: true
  attr :build, Build, required: true
  attr :show_author, :boolean, default: true

  def build_card(assigns) do
    assigns = assign(assigns, :ruleset, ruleset_for(assigns.build))

    ~H"""
    <article class="bcard" id={@id}>
      <div class="bcard-main">
        <.link navigate={~p"/builds/#{@build}"} class="bcard-name" id={@id <> "-link"}>
          {@build.name}
        </.link>

        <div class="bcard-meta">
          <span class="bcard-race">{race_label(@ruleset, @build)}</span>
          <span class="bcard-dot" aria-hidden="true">·</span>
          <span class="bcard-total">
            <b>{@build.total_level}</b> ур.
          </span>
          <span :if={@show_author && @build.user} class="bcard-dot" aria-hidden="true">·</span>
          <.link
            :if={@show_author && @build.user}
            patch={~p"/library?author=#{@build.user.id}"}
            class="bcard-author"
            id={@id <> "-author"}
          >
            {@build.user.email}
          </.link>
        </div>

        <div class="bcard-classes" id={@id <> "-classes"}>
          <span
            :for={entry <- class_entries(@ruleset, @build)}
            class="split-chip"
            id={@id <> "-class-" <> entry.class_id}
            style={Palette.style(entry.hue)}
            data-prc={entry.prc}
          >
            <span>{entry.name}</span>
            <span class="n">{entry.levels}</span>
          </span>
          <span :if={@build.class_levels == []} class="bcard-empty">классы не выбраны</span>
        </div>

        <p :if={@build.description not in [nil, ""]} class="bcard-desc">{@build.description}</p>
      </div>

      <div class="bcard-side">
        <span class="bcard-vis" data-vis={@build.visibility}>{visibility_label(@build)}</span>
        <span class="bcard-when">{date(@build.updated_at)}</span>
      </div>
    </article>
    """
  end

  @doc "The ruleset a saved build was built with, falling back to the current one."
  @spec ruleset_for(Build.t()) :: map()
  def ruleset_for(%Build{ruleset_version: version}) when is_binary(version) do
    case Data.ruleset(version) do
      {:ok, ruleset} -> ruleset
      _ -> Data.ruleset!()
    end
  end

  def ruleset_for(%Build{}), do: Data.ruleset!()

  @doc "`Гном (Dwarf)`, or a plain note when the build has no race yet."
  @spec race_label(map(), Build.t()) :: String.t()
  def race_label(_ruleset, %Build{race: nil}), do: "раса не выбрана"

  def race_label(ruleset, %Build{race: race}) do
    case Ids.fetch(ruleset, :races, race) do
      {:ok, id} -> "#{Labels.race_ru(ruleset, id)} (#{Labels.race_en(ruleset, id)})"
      :error -> race
    end
  end

  @doc """
  The class composition, biggest stake first.

  The order classes were *taken* in is not recoverable from these rows and is
  not claimed here — past level 20 it decides base attack outright (CLAUDE.md
  §3), so it belongs to the code, and the code is one click away.
  """
  @spec class_entries(map(), Build.t()) :: [map()]
  def class_entries(ruleset, %Build{class_levels: classes}) when is_list(classes) do
    classes
    |> Enum.sort_by(&{-&1.levels, &1.class_id})
    |> Enum.map(fn %{class_id: class_id, levels: levels} ->
      id = Ids.get(ruleset, :classes, class_id)

      %{
        class_id: class_id,
        name: if(id, do: Labels.class_name(ruleset, id), else: class_id),
        levels: levels,
        hue: Palette.hue(id),
        prc: Palette.prc(ruleset, id)
      }
    end)
  end

  def class_entries(_ruleset, %Build{}), do: []

  @doc "Russian word for a visibility, plus the group's name when there is one."
  @spec visibility_label(Build.t()) :: String.t()
  def visibility_label(%Build{visibility: :public}), do: "публичный"
  def visibility_label(%Build{visibility: :private}), do: "личный"

  def visibility_label(%Build{visibility: :group, group: %{name: name}}), do: "группа · #{name}"
  def visibility_label(%Build{visibility: :group}), do: "группа"

  @doc "A date, in the one format the interface uses."
  @spec date(DateTime.t() | nil) :: String.t()
  def date(%DateTime{} = at), do: Calendar.strftime(at, "%d.%m.%Y")
  def date(_), do: ""
end
