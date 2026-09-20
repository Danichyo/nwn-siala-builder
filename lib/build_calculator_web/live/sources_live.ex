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
        <h1 class="page-title">Источники</h1>
        <p class="page-sub">
          Игровые данные и часть описаний калькулятор берёт с вики NWN на Fandom и перерабатывает под правила Сиалы. Эта страница — атрибуция, которой требует лицензия этих текстов.
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
            — базовые (ванильные) правила Neverwinter Nights. Из статей этой вики разобраны таблицы прогрессии всех 23 классов (базовая атака, три спаса, скилл-поинты, спелл-слоты заклинателей), требования и описания 299 фитов и престиж-классов, 7 рас с их модификаторами характеристик, 28 навыков, 303 заклинания и правила эпических уровней 21–40. Это не отдельные цитаты — это основа расчётной модели калькулятора целиком, и без этого слоя данных калькулятор не считает вообще ничего.
          </p>
          <p>
            У каждого факта в наших данных сохранены название страницы-источника, номер её редакции и дата, когда мы её сняли, — по ним можно проверить любое число.
          </p>

          <h2 class="page-h2" id="sources-shard-heading">Правила шарда</h2>
          <p id="sources-shard-facts">
            Поверх ванильного слоя лежат правила приватного сервера, и переносятся они тем же способом — фактами с цитатой и ссылкой на источник. По классам таких фактов прочитано {@shard.classes.total}. В расчёт идут {@shard.classes.ours}: это те, что меняют числа, которые калькулятор показывает ({@shard.ours_receivers}). Из них {@shard.classes.applied} уже применены, а {@shard.classes.gaps} пока нет — они названы поимённо в списке неточностей в самом калькуляторе.
          </p>
          <p id="sources-shard-feats">
            Страницы фитов разбирает парсер, и фактов с них прочитано {@shard.feats.total}. Применены {@shard.feats.applied} — это тип фита, его требования, повторяемость и то, каким классам он выдаётся даром. Остальные {@shard.feats.unapplied} — проза, которой в модели нет места; из них {@shard.feats.gaps} — про то, что калькулятор показывает, и потому в том же списке неточностей.
          </p>
          <p id="sources-shard-skills">
            Страницы навыков разобраны вручную, как и классы, и фактов с них прочитано {@shard.skills.total}. В расчёт идут {@shard.skills.ours}: это те, что меняют числа, которые калькулятор показывает. Из них {@shard.skills.applied} уже применены, а {@shard.skills.gaps} пока нет — они названы поимённо в списке неточностей у билда, который вложился в этот навык.
          </p>
          <p id="sources-shard-not-ours">
            Не про наш расчёт — {@shard.classes.not_ours} фактов о классах, {@shard.feats.not_ours} о фитах и {@shard.skills.not_ours} о навыках: они про механики, которых калькулятор не считает вовсе ({@shard.not_our_receivers}). Из данных они не убраны и не спрятаны: у каждого помечено, что именно он меняет, поэтому в день, когда такая механика появится в расчёте, эти факты вернутся в список неточностей сами.
          </p>

          <%!-- Задача 3.88 (24.08.2026): методология переехала сюда целиком —
                на билд-экранах баннер и разбор по разрядам показываются,
                только пока в `ruleset.gaps` есть хоть одна настоящая дыра
                (`Gaps.data_tiers/1`, тир `:real`). Сегодня его нет, и это
                по-прежнему единственное место, отвечающее на «откуда
                правила» для решённых споров и принятых констант. Списки
                не сэмплированы (в отличие от панели конструктора) — здесь
                нет ограничения по месту, а вопрос «а покажи все» у страницы
                атрибуции звучит естественно. --%>
          <h2 class="page-h2" id="sources-methodology-heading">Как решены спорные места</h2>
          <p id="sources-methodology-intro">
            Часть фактов о правилах шарда — не дыра в расчёте, а решение: где вики спорят между собой (или где Fandom не называет то, что говорит игра), мы выбираем и говорим прямо, как именно; где ни одна страница не называет число словами, мы называем принятую константу с её источником. Список ниже — не пробелы, а список ТАКИХ решений, полностью, без сокращения.
          </p>

          <div :if={@gap_tiers.resolved != []} id="sources-gaps-resolved">
            <h3>Как решены расхождения источников</h3>
            <div :for={group <- @gap_tiers.resolved}>
              <h4>{group.kind} · {group.total}</h4>
              <ul>
                <li :for={item <- group.items}>{item}</li>
              </ul>
            </div>
          </div>

          <div :if={@gap_tiers.assumed != []} id="sources-gaps-assumed">
            <h3>Принятые допущения и константы</h3>
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
            <h3>Правила Сиалы, ещё не перенесённые в расчёт</h3>
            <div :for={group <- @gap_tiers.real}>
              <h4>{group.kind} · {group.total}</h4>
              <ul>
                <li :for={item <- group.items}>{item}</li>
              </ul>
            </div>
          </div>

          <h2 class="page-h2">Лицензия</h2>
          <p>
            Тексты статей NWN Wiki распространяются по лицензии
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
            >полный текст</.link>).
          </p>
          <p>
            Материал переработан: мы разобрали прозу статей в структурированные данные и для части классов, фитов, навыков и заклинаний скорректировали числа под правила приватного сервера, на который заточен этот калькулятор, — то есть это производная работа, а не копия исходного текста.
          </p>
          <p>
            По условию той же лицензии (share-alike) наш производный слой правил распространяется на тех же условиях — CC BY-SA 3.0: его можно копировать и перерабатывать дальше с тем же указанием источника.
          </p>

          <h2 class="page-h2" id="sources-icons-heading">Иконки фитов и заклинаний</h2>
          <p id="sources-icons-text">
            Иконки взяты с <.link
              href="https://nwn.fandom.com/"
              target="_blank"
              rel="noopener noreferrer"
              id="sources-icons-fandom-link"
            >
              NWN Wiki (Fandom)
            </.link>. Это элементы интерфейса самой игры Neverwinter Nights: права на них принадлежат
            <strong>BioWare</strong>
            и <strong>Beamdog</strong>, и лицензия CC BY-SA, под которой публикуются тексты вики, на изображения <strong>не распространяется</strong>.
          </p>
          <p id="sources-icons-disclaimer">
            Калькулятор — некоммерческий фанатский инструмент и не связан ни с BioWare, ни с Beamdog, ни с Fandom. По просьбе правообладателя изображения будут убраны.
          </p>

          <h2 class="page-h2" id="sources-disclaimer-heading">Не аффилированы</h2>
          <p id="sources-disclaimer">
            Проект не связан с BioWare, Beamdog, Wizards of the Coast, Fandom или администрацией шарда, на который он заточен. Neverwinter Nights и Dungeons &amp; Dragons — товарные знаки соответствующих владельцев; здесь они упомянуты только чтобы описать игровые правила.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    ruleset = Data.ruleset!()

    {:ok,
     socket
     |> assign(:page_title, "Источники · Калькулятор билдов Сиалы")
     |> assign(:shard, shard_facts(ruleset))
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
