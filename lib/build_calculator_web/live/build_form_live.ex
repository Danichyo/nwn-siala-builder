defmodule BuildCalculatorWeb.BuildFormLive do
  @moduledoc """
  Saving a build, and editing what was saved about it.

  ## What is actually stored

  The code, and nothing about the character besides. Name, description and
  visibility are the whole form; the level ladder, the feats and the ranks stay
  inside the code, which versions itself (`BuildCalculator.Library.Build`). So
  this screen never touches the build — it arrives in `?b=<code>` from the
  constructor and is handed to the context untouched.

  It is still *decoded* here, to show the player what they are about to save.
  A code that will not decode is refused before the form appears rather than
  after the save fails.

  ## How a guest gets here without losing their work

  They do not get here — the router does. `/builds/new` sits behind
  `require_authenticated_user`, whose plug stores the full path (query string
  included) before redirecting to log-in, so the build comes back with them.
  See `BuildCalculatorWeb.UserAuth`.

  ## Authorisation

  `group_id` is never cast by the changeset: `Library` looks it up against the
  caller's own memberships, so choosing a group you are not in fails the
  changeset instead of quietly publishing into it. Editing is guarded by the
  context's `where`, not by this module — `can_edit?/2` here only decides
  whether to draw the form at all.

  That refusal has one visible home, `#build-group-error`, which does not live
  inside the group select. The select is only drawn for people who are in a
  group at all, and an error attached to a field that may not be drawn is an
  error nobody reads: the save simply did nothing.
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Accounts
  alias BuildCalculator.Encoding
  alias BuildCalculator.Library
  alias BuildCalculator.Library.Build
  alias BuildCalculator.Rules.Build, as: Character
  alias BuildCalculatorWeb.Builder.{Labels, Palette}

  @visibilities [
    {"Личный — виден только мне", "private"},
    {"Публичный — в общей ленте", "public"},
    {"Группа — виден участникам группы", "group"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} active={:mine} />

      <div class="page page-narrow" id="build-form-page">
        <h1 class="page-title">
          {if @live_action == :new, do: "Сохранить билд", else: "Правка билда"}
        </h1>

        <div class="bform-preview" id="build-preview">
          <div class="bcard-meta">
            <span>{Labels.race_ru(@ruleset, @character.race)} ({Labels.race_en(
              @ruleset,
              @character.race
            )})</span>
            <span class="bcard-dot" aria-hidden="true">·</span>
            <span class="bcard-total"><b>{Character.character_level(@character)}</b> ур.</span>
          </div>
          <div class="bcard-classes">
            <span
              :for={{class, levels} <- Character.class_levels(@character)}
              class="split-chip"
              id={"preview-class-#{class}"}
              style={Palette.style(Palette.hue(class))}
              data-prc={Palette.prc(@ruleset, class)}
            >
              <span>{Labels.class_name(@ruleset, class)}</span>
              <span class="n">{levels}</span>
            </span>
          </div>
          <p class="page-sub">
            Хранится код билда, а не разобранные колонки — ссылка и сохранение это одно и то же.
            <.link navigate={~p"/?b=#{@code}"} id="preview-open">Открыть в конструкторе</.link>
          </p>
        </div>

        <.form for={@form} id="build-form" class="form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} type="text" label="Название" required maxlength="120" />
          <.input
            field={@form[:description]}
            type="textarea"
            label="Описание"
            rows="4"
            maxlength="4000"
          />
          <.input
            field={@form[:visibility]}
            type="select"
            label="Видимость"
            options={@visibilities}
            id="build-visibility"
          />

          <%= if @visibility == :group do %>
            <%!-- Без `field=`: поле само рисует свои ошибки, а место у них
                  ниже одно на все случаи — см. комментарий у #build-group-error. --%>
            <.input
              :if={@groups != []}
              type="select"
              name="build[group_id]"
              value={@form[:group_id].value}
              label="Группа"
              options={group_options(@groups)}
              prompt="выберите группу"
              id="build-group"
            />
            <p :if={@groups == []} class="feat-why" id="no-groups">
              Вы пока ни в одной группе. <.link navigate={~p"/groups"} id="to-groups">Создать или вступить</.link>.
            </p>
          <% end %>

          <%!-- ⚠️ Ошибка про группу стоит СНАРУЖИ ветки и не привязана к полю.
                Раньше `put_group/3` клал её на `group_id`, а поле рисовалось
                только тем, кто состоит хотя бы в одной группе: у остальных
                сообщению было некуда лечь, и «Сохранить» молча ничего не делал.
                Место для сообщения не должно зависеть от того, отрисовалось ли
                поле — иначе тот же баг вернётся при следующей правке формы. --%>
          <p :if={@group_errors != []} class="feat-why" id="build-group-error">
            {Enum.join(@group_errors, " ")}
          </p>

          <div class="form-row">
            <button
              type="submit"
              class="btn btn-primary"
              id="build-save"
              phx-disable-with="Сохраняем…"
            >
              Сохранить
            </button>
            <.link navigate={cancel_path(@build)} class="btn" id="build-cancel">Отмена</.link>
            <button
              :if={@live_action == :edit}
              type="button"
              class="btn"
              id="build-delete"
              phx-click="delete"
              data-confirm="Удалить билд? Ссылка на код продолжит работать, запись — нет."
            >
              Удалить
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Сохранить билд · Калькулятор билдов Сиалы")
      |> assign(:visibilities, @visibilities)
      |> assign(:groups, Accounts.list_groups(socket.assigns.current_scope))

    {:ok, start(socket, socket.assigns.live_action, params)}
  end

  defp start(socket, :new, params) do
    code = params["b"]

    case Encoding.decode(code) do
      {:ok, %{ruleset: ruleset, build: character}} ->
        build = %Build{code: code, visibility: :private}

        socket
        |> assign(:build, build)
        |> assign(:code, code)
        |> assign(:ruleset, ruleset)
        |> assign(:character, character)
        |> assign_form(
          Library.change_build(build, %{
            "name" => given_name(params) || suggested_name(ruleset, character)
          })
        )

      {:error, reason} ->
        socket
        |> put_flash(:error, Labels.decode_error(reason))
        |> push_navigate(to: ~p"/")
    end
  end

  defp start(socket, :edit, %{"id" => id}) do
    with {:ok, build} <- Library.fetch_build(socket.assigns.current_scope, id),
         true <- Library.can_edit?(socket.assigns.current_scope, build),
         {:ok, %{ruleset: ruleset, build: character}} <- Encoding.decode(build.code) do
      socket
      |> assign(:build, build)
      |> assign(:code, build.code)
      |> assign(:ruleset, ruleset)
      |> assign(:character, character)
      |> assign_form(Library.change_build(build, %{}))
    else
      _ ->
        socket
        |> put_flash(:error, "Такого билда нет или он не ваш.")
        |> push_navigate(to: ~p"/library/mine")
    end
  end

  @impl true
  def handle_event("validate", %{"build" => params}, socket) do
    changeset =
      socket.assigns.build
      |> Library.change_build(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset, params)}
  end

  def handle_event("save", %{"build" => params}, socket) do
    %{current_scope: scope, build: build, live_action: action} = socket.assigns

    result =
      case action do
        :new -> Library.create_build(scope, Map.put(params, "code", socket.assigns.code))
        :edit -> Library.update_build(scope, build, params)
      end

    case result do
      {:ok, saved} ->
        {:noreply,
         socket
         |> put_flash(:info, "Билд сохранён.")
         |> push_navigate(to: ~p"/builds/#{saved}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert), params)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Такого билда нет или он не ваш.")
         |> push_navigate(to: ~p"/library/mine")}
    end
  end

  def handle_event("delete", _params, socket) do
    case Library.delete_build(socket.assigns.current_scope, socket.assigns.build) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Билд удалён.")
         |> push_navigate(to: ~p"/library/mine")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Билд уже удалён.")}
    end
  end

  defp assign_form(socket, changeset, params \\ %{}) do
    visibility =
      case params["visibility"] do
        "public" -> :public
        "group" -> :group
        "private" -> :private
        _ -> Ecto.Changeset.get_field(changeset, :visibility) || :private
      end

    socket
    |> assign(:form, to_form(changeset, as: "build"))
    |> assign(:visibility, visibility)
    |> assign(:group_errors, group_errors(changeset))
  end

  # Только после попытки сохранить — ровно как это делает `<.input>`:
  # у changeset'а без `action` ошибок нет вовсе, и открытая форма не должна
  # ругаться на то, чего человек ещё не нажимал.
  defp group_errors(%Ecto.Changeset{action: nil}), do: []

  defp group_errors(%Ecto.Changeset{errors: errors}) do
    for {:group_id, error} <- errors, do: translate_error(error)
  end

  # A name the constructor already knows — an imported text block names its
  # build, and losing that on the way to the save form would be a small lie of
  # the same family as losing a feat. Only a draft: the field stays editable.
  defp given_name(params) do
    case params["name"] do
      name when is_binary(name) -> name |> String.trim() |> String.slice(0, 120) |> nil_if_blank()
      _ -> nil
    end
  end

  defp nil_if_blank(""), do: nil
  defp nil_if_blank(name), do: name

  # A first draft of the name, in the shape the community writes builds in
  # (CLAUDE.md §3): "Fighter 10 / Dwarven defender 23". It is only a suggestion —
  # the field is editable and required either way.
  defp suggested_name(ruleset, %Character{} = character) do
    # ⚠️ Раньше здесь стоял `[] ->`, и он не матчился НИКОГДА: `class_levels/1`
    # возвращает карту. Пустой билд не получал «Новый билд», а проваливался
    # во вторую ветку, где `Enum.map_join` по пустой карте даёт `""` — то есть
    # форма открывалась с пустым обязательным полем имени. Нашёл dialyzer.
    case Character.class_levels(character) do
      classes when map_size(classes) == 0 ->
        "Новый билд"

      classes ->
        classes
        |> Enum.sort_by(fn {class, levels} -> {-levels, Atom.to_string(class)} end)
        |> Enum.map_join(" / ", fn {class, levels} ->
          "#{Labels.class_name(ruleset, class)} #{levels}"
        end)
    end
  end

  defp group_options(groups), do: Enum.map(groups, &{&1.name, &1.id})

  defp cancel_path(%Build{id: nil}), do: ~p"/library/mine"
  defp cancel_path(%Build{} = build), do: ~p"/builds/#{build}"
end
