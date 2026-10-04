defmodule BuildCalculatorWeb.SourcesLive do
  @moduledoc """
  Attribution for the Fandom text this app's rule data is built on.

  Static content, but it is a LiveView rather than a plain controller for the
  same reason every other screen is: one rendering path, `Layouts.app` and
  `site_header` for free, and it sits in the `:current_user` `live_session`
  in the router so a guest who never signs in can still read it (`AGENTS.md`
  §Authentication — routes that work with or without authentication).

  ## What is on this page, and why only this much

  CC BY-SA 3.0 asks for four things: name the source, name the license, say
  that the material was changed, and carry the same license forward on the
  derivative (share-alike). That is exactly the four sections below — nothing
  about "legal position" or warranties is added, because that was never asked
  for and is not this project's call to make (CLAUDE.md §3 "Лицензии — не
  забыть").

  The Siala wiki is deliberately **not** named here — a direct product
  decision (Dan, 04.08.2026): it carries no license of its own (CLAUDE.md
  §3), and whether/how to credit it is a separate conversation. This page
  only discharges the Fandom obligation.

  ## Icons are a second, separately-licensed block — not folded into the above

  Task 3.50 (Dan, 18.08.2026): "Иконки фитов и заклинаний" sits **below** the
  CC BY-SA section, not inside it, on purpose. The 541 feat/spell icon images
  under `priv/static/icons/` (`mix wiki.fetch.icons`) are Fandom-hosted, but
  Fandom does not own them — they are BioWare/Beamdog game interface assets,
  and CC BY-SA (which covers wiki *text*) does not apply to them at all.
  Naming only Fandom here would say the license does cover them, which is the
  wrong kind of wrong for an attribution page: not a missing credit, a false
  one. Skills and classes are not mentioned in that block because neither
  carries an icon on Fandom — there is nothing there to credit.

  ## The license, verified rather than assumed

  Checked 04.08.2026 against the wiki's own MediaWiki API, not written from
  memory (the whole point of an attribution page is that it is not a guess):

      https://nwn.fandom.com/api.php?action=query&meta=siteinfo&siprop=rightsinfo&format=json
      => {"rightsinfo":{"url":"https://www.fandom.com/licensing","text":"CC-BY-SA"}}

  That confirms nwn.fandom.com uses Fandom's default license (not one of the
  NC variants some wikis opt into) but names no version. The version comes
  from Fandom's own licensing page, `https://www.fandom.com/licensing`
  (fetched through a text-extraction proxy, since the page itself sits behind
  a Cloudflare challenge that blocks a plain HTTP client):

      "Except where otherwise permitted, the text on Fandom communities
      (known as "wikis") is licensed under the Creative Commons Attribution-
      Share Alike License 3.0 (Unported) (CC BY-SA)."

  Together: CC BY-SA 3.0 Unported, linking to
  `creativecommons.org/licenses/by-sa/3.0/`.

  ## Scope of what is actually borrowed

  `priv/rules/vanilla/` is not a handful of quoted descriptions — it is
  parsed wholesale from Fandom wikitext: every class's progression tables
  (base attack, all three saves, skill points, caster spell slots), every
  feat and prestige class requirement, every race's ability modifiers, every
  skill, every spell, and the epic-level rules. The counts below are read
  from those files, not typed from memory, so a future edit to the data
  cannot silently make this page lie:

      classes.json  -> 23
      feats.json    -> 299
      races.json    -> 7
      skills.json   -> 28
      spells.json   -> 303

  ## The shard's own facts, and why they are counted here

  Task 3.28 (Dan, 10.08.2026): a gap is a hole in the **answer**, not in what we
  know. Most of the shard's class facts are about mechanics the calculator gives
  no answer about at all — damage, effect duration, immunities, summons, poisons,
  traps, movement speed, the familiar, class items, buffs — so they stopped
  counting towards the «пробелов в данных» figure in the constructor, where they
  were the bulk of a list a player is meant to react to.

  ⚠ **Stopping counting is not hiding**, and this section is the difference. Every
  fact is still read, still carries what it changes (`changes[].affects`), and is
  counted here by `Rules.GapReceivers.census/1` — from the data, not typed in. The
  moment one of those mechanics reaches the model, its facts return to the gap
  list on their own.

  ## Three layers, three paragraphs, never one sum

  Since 14.08.2026 the same markup exists on the **feat** and the **skill**
  layer too, so the census counts both — and the page prints all three layers
  apart. Adding them up would be the easy mistake: 126 class facts are prose a
  human transcribed off the shard's pages, 196 feat facts are mostly the four
  bold labels a parser read off them, 53 skill facts are prose again (a skill
  record carries no machine-read label of its own, same as a class's), and
  «прочитано 375» would answer no question anybody has.

  One asymmetry is printed rather than smoothed over, because smoothing it is
  how a page starts lying quietly: **feats have no `ours` figure.** Only the
  facts that failed to apply are labelled there; the other 175 applied, and the
  rule «no label means it is still a gap» would count them as ours and pass
  that off as a reading somebody made. `applied` says what they are. Classes
  and skills carry no such asymmetry — every fact of theirs is labelled, so
  their own `ours` is a real reading, not a safety net.

  ⚠ **Until 14.08.2026 the skill layer was the second asymmetry**: counted
  here with its own numbers (53 facts, 48 unapplied) but not yet classified,
  so it stayed out of the header's figure on purpose rather than looking
  absent. Task "навыки: получатели у фактов" (data-miner) closed that — the
  skill layer's paragraph below now reads exactly like the class layer's.

  The Siala wiki is still not named as a source (see above) — this says what our
  own data holds, and links nowhere.

  ## Where the resolved-conflicts and accepted-constants lists moved (task 3.88, 24.08.2026)

  `ruleset.gaps` used to print in full on both build screens — real holes,
  resolved source conflicts and accepted constants all in one panel. Task
  3.88 (Dan, looking at a 17-entry list that was mostly the latter two after
  task 3.86 closed the last real one): "для пользователей я предлагаю дыры
  больше не показывать" — a list of *decisions* is not a list of
  imprecisions, and showing it under a "part of the rules is missing"
  header would be the wrong kind of dishonest. The build screens now gate
  that panel on there being an actual hole (`Gaps.data_tiers/1`'s `:real`
  tier); "прячем до момента появления дыр, в sources можно оставить" is why
  the two sections below exist — the methodology itself did not stop being
  true just because the list is currently empty of real holes, and "откуда
  правила" is exactly this page's job.

  ## Two editions, one page (task 4.4)

  The page serves both sites, and everything it says about the SHARD is said
  about our data, so it is gated on the data: `Gaps.shard_facts?/1` — does the
  ruleset carry a shard layer at all. Without one (vanilla) the «Правила
  шарда» section, the clause about numbers corrected for the private server
  and the shard administration in the disclaimer are gone, not rendered as
  zeros; the Fandom CC BY-SA attribution stays on both. Sentences that only
  *name* the site's rules («правила Сиалы») go through `gettext` with a
  neutral English msgid and the old Russian text as the translation (the head
  of task 4.4's section in `ru/default.po`).
  """
  use BuildCalculatorWeb, :live_view

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.GapReceivers
  alias BuildCalculatorWeb.Builder.{Gaps, Labels}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.site_header current_scope={@current_scope} />

      <div class="page page-narrow" id="sources-page">
        <h1 class="page-title">{gettext("Sources")}</h1>
        <%!-- Задача 4.4: вводная — через `gettext`. Английский msgid говорит
              «the rules it computes»: сайт считает один ruleset, и чьи это
              правила, ясно без имени. Русский перевод — прежний текст
              с «правила Сиалы» (русский каталог — язык сиальской редакции,
              шапка раздела 4.4 в `ru/default.po`). --%>
        <p class="page-sub" id="sources-intro">
          {gettext(
            "The calculator takes game data and part of the descriptions from the NWN wiki on Fandom and adapts them to the rules it computes. This page is the attribution the license of those texts requires."
          )}
        </p>

        <div class="sources-body">
          <h2 class="page-h2">NWN Wiki (Fandom)</h2>
          <p>
            <.link
              href="https://nwn.fandom.com/"
              target="_blank"
              rel="noopener noreferrer"
              id="sources-fandom-link"
            >
              nwn.fandom.com
            </.link>
            {gettext(
              "— the base (vanilla) rules of Neverwinter Nights. From this wiki's articles we parsed the progression tables of all 23 classes (base attack, the three saves, skill points, casters' spell slots), the requirements and descriptions of 299 feats and prestige classes, 7 races with their ability modifiers, 28 skills, 303 spells and the rules for epic levels 21–40. These are not a few separate quotes — this is the foundation of the calculator's whole model, and without this data layer the calculator computes nothing at all."
            )}
          </p>
          <p>
            {gettext(
              "Every fact in our data keeps the title of its source page, the page's revision number and the date we took it — any number can be checked against them."
            )}
          </p>

          <%!-- Задача 4.4: раздел — про факты шарда в НАШИХ данных, и у правил
                без слоя шарда (ваниль) он был стеной нулей. Ворота —
                `@shard_facts?` (`Gaps.shard_facts?/1`, по данным, не по имени
                ruleset'а): раздел гаснет сам, как только фактов шарда нет.
                Блок `if`, а не обёртка: разметка у Сиалы та же, что была. --%>
          <%= if @shard_facts? do %>
            <h2 class="page-h2" id="sources-shard-heading">{gettext("Shard rules")}</h2>
            <%!-- Задача 4.17: у каждого абзаца несколько чисел, и одним
                  `ngettext` их не согласовать — английский поставлен так,
                  чтобы число не требовало формы (после двоеточия или
                  в скобках); русский — прежний литерал. --%>
            <p id="sources-shard-facts">
              {gettext(
                "The private server's rules sit on top of the vanilla layer and are carried over the same way — as facts with a quote and a link to the source. Class facts read: %{total}. Counted in the calculation: %{ours} — those that change the numbers the calculator shows (%{receivers}). Of these, applied already: %{applied}; not yet: %{gaps} — they are named one by one in the calculator's own list of what we can't calculate yet.",
                total: @shard.classes.total,
                ours: @shard.classes.ours,
                receivers: @shard.ours_receivers,
                applied: @shard.classes.applied,
                gaps: @shard.classes.gaps
              )}
            </p>
            <p id="sources-shard-feats">
              {gettext(
                "Feat pages are read by a parser; facts read from them: %{total}. Applied: %{applied} — the feat's type, its requirements, whether it can be taken more than once and which classes get it for free. The rest (%{unapplied}) is plain text the model has no place for; the part of it about what the calculator shows (%{gaps}) is on the same list of what we can't calculate yet.",
                total: @shard.feats.total,
                applied: @shard.feats.applied,
                unapplied: @shard.feats.unapplied,
                gaps: @shard.feats.gaps
              )}
            </p>
            <p id="sources-shard-skills">
              {gettext(
                "Skill pages were read by hand, like the classes; facts read from them: %{total}. Counted in the calculation: %{ours} — those that change the numbers the calculator shows. Of these, applied already: %{applied}; not yet: %{gaps} — they are named one by one in the list of what we can't calculate yet for a build that puts ranks in that skill.",
                total: @shard.skills.total,
                ours: @shard.skills.ours,
                applied: @shard.skills.applied,
                gaps: @shard.skills.gaps
              )}
            </p>
            <p id="sources-shard-not-ours">
              {gettext(
                "Not about our calculation — facts about classes: %{classes}, about feats: %{feats}, about skills: %{skills}. They concern mechanics the calculator does not compute at all (%{receivers}). They have not been removed from the data or hidden: each one is marked with what it changes, so the day such a mechanic enters the calculation, these facts return to the list of what we can't calculate yet on their own.",
                classes: @shard.classes.not_ours,
                feats: @shard.feats.not_ours,
                skills: @shard.skills.not_ours,
                receivers: @shard.not_our_receivers
              )}
            </p>
          <% end %>

          <%!-- Задача 3.88 (24.08.2026): методология переехала сюда целиком —
                на билд-экранах баннер и разбор по разрядам показываются,
                только пока в `ruleset.gaps` есть хоть одна настоящая дыра
                (`Gaps.data_tiers/1`, тир `:real`). Сегодня его нет, и это
                по-прежнему единственное место, отвечающее на «откуда
                правила» для решённых споров и принятых констант. Списки
                не сэмплированы (в отличие от панели конструктора) — здесь
                нет ограничения по месту, а вопрос «а покажи все» у страницы
                атрибуции звучит естественно. --%>
          <%!-- Задача 4.4: вводная и три заголовка раздела — через `gettext`
                (заголовки открылись на ванили после 4.3). Английский вводной
                говорит «the rules», русский перевод — прежний текст
                с «правилах шарда» (шапка раздела 4.4 в `ru/default.po`). --%>
          <h2 class="page-h2" id="sources-methodology-heading" phx-no-format>{gettext("How disputed points were settled")}</h2>
          <p id="sources-methodology-intro">
            {gettext(
              "Some facts about the rules are not a hole in the calculation but a decision: where the wikis disagree with each other (or where Fandom does not name what the game says), we choose and say plainly how; where no page states a number in words, we name the accepted constant with its source. The list below is not what we can't calculate but a list of SUCH decisions, in full, uncut."
            )}
          </p>

          <div :if={@gap_tiers.resolved != []} id="sources-gaps-resolved">
            <h3>{gettext("How source disagreements were resolved")}</h3>
            <div :for={group <- @gap_tiers.resolved}>
              <h4>{group.kind} · {group.total}</h4>
              <ul>
                <li :for={item <- group.items}>{item}</li>
              </ul>
            </div>
          </div>

          <div :if={@gap_tiers.assumed != []} id="sources-gaps-assumed">
            <h3>{gettext("Accepted assumptions and constants")}</h3>
            <div :for={group <- @gap_tiers.assumed}>
              <h4>{group.kind} · {group.total}</h4>
              <ul>
                <li :for={item <- group.items}>{item}</li>
              </ul>
            </div>
          </div>

          <%!-- ⚠️ НЕ прячем настоящие дыры отсюда, если они вдруг появятся:
                эта страница — не замена конструктору, но молчать про них
                здесь означало бы, что «откуда правила» на минуту перестаёт
                быть честным ответом. Сегодня список пуст (задача 3.86), и
                положительный сценарий проверен синтетическим ruleset'ом
                в тестах, а не живыми данными — живые сегодня нуль. --%>
          <div :if={@gap_tiers.real != []} id="sources-gaps-real">
            <h3>{gettext("Rules not yet carried into the calculation")}</h3>
            <div :for={group <- @gap_tiers.real}>
              <h4>{group.kind} · {group.total}</h4>
              <ul>
                <li :for={item <- group.items}>{item}</li>
              </ul>
            </div>
          </div>

          <h2 class="page-h2">{gettext("License")}</h2>
          <p>
            {gettext("The text of NWN Wiki articles is licensed under")}
            <.link
              href="https://creativecommons.org/licenses/by-sa/3.0/"
              target="_blank"
              rel="license noopener noreferrer"
              id="sources-license-link"
            >
              Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)
            </.link>
            (<.link
              href="https://creativecommons.org/licenses/by-sa/3.0/legalcode"
              target="_blank"
              rel="noopener noreferrer"
              id="sources-legalcode-link"
            >{gettext("full text")}</.link>).
          </p>
          <%!-- Задача 4.4: «скорректировали числа под правила приватного
                сервера» правда только о правилах со слоем шарда — ворота
                `@shard_facts?`, как у раздела «Правила шарда» выше. Без слоя
                шарда (ваниль) остаётся то, что верно для любых правил: проза
                разобрана в данные. --%>
          <p id="sources-changed">
            <%= if @shard_facts? do %>
              {gettext(
                "The material has been changed: we parsed the articles' prose into structured data and, for some classes, feats, skills and spells, adjusted the numbers to the rules of the private server this calculator is built for — so this is a derivative work, not a copy of the original text."
              )}
            <% else %>
              {gettext(
                "The material has been changed: we parsed the articles' prose into structured data — so this is a derivative work, not a copy of the original text."
              )}
            <% end %>
          </p>
          <p>
            {gettext(
              "Under the same license's share-alike condition, our derived rules layer is distributed on the same terms — CC BY-SA 3.0: you may copy and adapt it further, crediting the source the same way."
            )}
          </p>

          <h2 class="page-h2" id="sources-icons-heading">{gettext("Feat and spell icons")}</h2>
          <%!-- Задача 4.17: фраза разрезана тегами (ссылка, два `<strong>`
                и выделенный хвост) — порядок кусков задаёт разметка, каждый
                перевод обязан в него укладываться. Последнее предложение
                собрано из двух сообщений: по-русски выделено «не
                распространяется», по-английски — «does not cover the
                images»; «на изображения» стоит в русском переводе куска
                перед выделением. --%>
          <%!-- Задача 4.18: текст ссылки вплотную к тегам — перенос строки
                внутри `<a>` рисовался пробелом перед точкой («(Fandom) .»). --%>
          <p id="sources-icons-text">
            {gettext("The icons are taken from")} <.link
              href="https://nwn.fandom.com/"
              target="_blank"
              rel="noopener noreferrer"
              id="sources-icons-fandom-link"
            >NWN Wiki (Fandom)</.link>. {gettext(
              "They are interface elements of the game Neverwinter Nights itself: the rights to them belong to"
            )}
            <strong>BioWare</strong>
            {gettext("and")} <strong>Beamdog</strong>{gettext(
              ", and the CC BY-SA license the wiki's texts are published under"
            )} <strong>{gettext("does not cover the images")}</strong>.
          </p>
          <p id="sources-icons-disclaimer">
            {gettext(
              "The calculator is a non-commercial fan tool and is not affiliated with BioWare, Beamdog or Fandom. The images will be removed at the rights holder's request."
            )}
          </p>

          <%!-- Задача 4.54: строка о счётчике посещений — только когда он
                включён (`Layouts.analytics?/0`): выключенный не о чем описывать.
                Что пишется и чего нет — `BuildCalculator.Analytics`. --%>
          <%= if Layouts.analytics?() do %>
            <h2 class="page-h2" id="sources-analytics-heading">{gettext("Visit counter")}</h2>
            <p id="sources-analytics">
              {gettext(
                "We count visits ourselves, without cookies and without third-party scripts. A visit counts only when a page opens in a live browser, so link previews and most bots are left out. To tell visitors apart within one day we keep a one-way hash of the address and browser name mixed with a key that changes every day and is never written down; the address and browser name themselves are not stored. We record which kind of page was opened (a build page, never the build itself), the name of the site you came from, the link's utm tags, and calculator events: a build opened by link, an export downloaded, an import, a build reaching the last non-epic level and the level cap. Not a single build ends up in these statistics."
              )}
            </p>
          <% end %>

          <h2 class="page-h2" id="sources-disclaimer-heading">{gettext("Not affiliated")}</h2>
          <%!-- Задача 4.4: администрацию шарда оговорка называет потому, что
                в наших данных лежат правила шарда, — те же ворота
                `@shard_facts?`. Сиальский текст прежний дословно. --%>
          <p id="sources-disclaimer">
            <%= if @shard_facts? do %>
              {gettext(
                "This project is not affiliated with BioWare, Beamdog, Wizards of the Coast, Fandom or the administration of the shard it is built for. Neverwinter Nights and Dungeons & Dragons are trademarks of their respective owners; they are mentioned here only to describe the game rules."
              )}
            <% else %>
              {gettext(
                "This project is not affiliated with BioWare, Beamdog, Wizards of the Coast or Fandom. Neverwinter Nights and Dungeons & Dragons are trademarks of their respective owners; they are mentioned here only to describe the game rules."
              )}
            <% end %>
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    ruleset = Data.ruleset!(Edition.ruleset())

    {:ok,
     socket
     |> assign(:page_title, Edition.page_title(gettext("Sources")))
     |> assign(:shard, shard_facts(ruleset))
     # Задача 4.4: есть ли у правил сайта слой шарда — ворота всего, что эта
     # страница говорит о шарде (`Gaps.shard_facts?/1`, по данным).
     |> assign(:shard_facts?, Gaps.shard_facts?(ruleset))
     |> assign(:gap_tiers, Gaps.data_tiers(gaps_source_for_page(ruleset)))}
  end

  # `SourcesLive.moduledoc` — the Siala wiki is never named on this page (Dan,
  # 04.08.2026: it carries no license of its own, crediting it is a separate
  # conversation not yet had); `SiteFooterTest`, "вики Сиалы не упомянута
  # нигде на странице", enforces it. One gap FORM's own translated text says
  # so by construction — `Labels.gap({:assumed, :class_unavailable_feats_vanilla},
  # _)` reads "the Siala wiki is silent about this" — so it is excluded here,
  # by its exact tuple, not by matching the Russian string. A string filter
  # would also swallow any future gap that happens to *quote* the wiki
  # honestly; naming the one form this page's decision is actually about
  # keeps the exclusion legible instead of a silent net. The constructor and
  # view screens are unaffected — `Gaps.data_tiers/1` there still reads
  # `ruleset.gaps` whole, and naming the wiki is normal in-app vocabulary
  # everywhere except here.
  @excluded_from_sources MapSet.new([{:assumed, :class_unavailable_feats_vanilla}])

  defp gaps_source_for_page(ruleset) do
    update_in(ruleset.gaps, &Enum.reject(&1, fn gap -> gap in @excluded_from_sources end))
  end

  # Числа считаются из данных, а не вписаны: страница про честность источников
  # не имеет права держать цифру, которую нельзя проверить. Русские имена
  # получателей — у веб-слоя (`Labels`), сами получатели — из ruleset'а.
  #
  # ⚠️ С 14.08.2026 `census/1` считает слои раздельно (`classes` / `feats` /
  # `skills`), и складывать их страница НЕ имеет права: 126 фактов о классах —
  # это прочитанная человеком проза, а 196 о фитах — в основном четыре жирных
  # лейбла, снятых парсером со страницы. Сумма отвечала бы на вопрос, которого
  # никто не задавал, поэтому у каждого числа на странице назван слой.
  #
  # ⚠️ И у фитов НЕ печатается `ours`: разметку получили только те факты, что
  # не легли в модель, а остальные 175 применены и метки не несут вовсе —
  # по правилу «нет метки, значит наш» они попали бы в это число и выдали бы
  # за классификацию то, чего никто не читал. Их роль отвечает `applied`.
  defp shard_facts(ruleset) do
    census = GapReceivers.census(ruleset)
    vocabulary = GapReceivers.vocabulary(ruleset)

    # ⚠️ Наши получатели — ВСЕ объявленные, а не только те, у которых сегодня
    # есть факт: фраза отвечает на «что калькулятор показывает». Не наши —
    # наоборот, только встреченные, причём по всем трём слоям сразу (навыки
    # присоединились 14.08.2026), потому что фраза про них отвечает на «про
    # что вот эти отброшенные факты», и список обязан сходиться с числами рядом.
    #
    # ⚠️ Числа здесь сознательно НЕ названы даже в комментарии: `census`
    # считает их из данных, и вписанное число устарело бы в тот же день
    # (10.08.2026 отброшенных стало 73 вместо 70 — решение Dan про баффы).
    # Строка в справке, называющая число, которое рядом уже посчитано, —
    # ровно то, на чём проект горел трижды (CLAUDE.md §9).
    Map.merge(census, %{
      ours_receivers: vocabulary.our |> Labels.gap_receivers() |> Enum.join(", "),
      not_our_receivers:
        [census.classes, census.feats, census.skills]
        |> Enum.flat_map(& &1.not_our_receivers)
        |> Enum.map(&elem(&1, 0))
        |> Labels.gap_receivers()
        |> Enum.join(", ")
    })
  end
end
