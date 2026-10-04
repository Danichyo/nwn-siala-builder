// Regression tests for `.FeatInfo` (`BuildCalculatorWeb.BuilderComponents`,
// `feat_info/1`) — see the moduledoc there for what the hook is and why it
// exists. This file targets one specific, already-shipped-broken behaviour
// (AGENT_QUEUE.md 3.138 П1): the "×" close button once did not close the
// panel at all, because `close({restoreFocus: true})` focuses the trigger,
// and the trigger's own `focus` listener reopens the panel — same element,
// same hook. Fixed by `suppressAutoOpen`; this file exists so it cannot
// come back silently.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderComponents.FeatInfo";

let dom;
let hookDefinition;

before(async () => {
  dom = installDom({ width: 1440, height: 900 });
  hookDefinition = await loadHook(HOOK_NAME);
});

after(() => {
  uninstallDom();
});

let nextId = 0;

function mountTrigger() {
  const el = dom.document.createElement("span");
  el.id = `feat-info-test-${nextId++}`;
  el.setAttribute("tabindex", "0");
  el.dataset.featName = "Toughness";
  el.dataset.featDescription = "Gain extra hit points.";
  el.dataset.featChanged = "false";
  el.dataset.labelClose = "Закрыть";
  dom.document.body.appendChild(el);
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();
  return { el, hook };
}

function unmount({ el, hook }) {
  hook.destroyed();
  el.remove();
}

function click(el) {
  el.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
}

function panelEl() {
  return dom.document.getElementById("feat-info-panel");
}

test("клик по триггеру открывает панель с описанием фита", () => {
  const t = mountTrigger();
  click(t.el);
  const panel = panelEl();
  assert.equal(panel.dataset.open, "1");
  assert.ok(panel.textContent.includes("Toughness"));
  unmount(t);
});

test('кнопка "×" закрывает панель и НЕ открывает её заново (регрессия 24.08.2026)', () => {
  const t = mountTrigger();
  click(t.el);
  const panel = panelEl();
  assert.equal(panel.dataset.open, "1", "панель должна быть открыта до закрытия");

  const closeButton = panel.querySelector(".feat-info-close");
  assert.ok(closeButton, "кнопка закрытия должна быть отрисована в шапке панели");
  click(closeButton);

  assert.equal(
    panel.dataset.open,
    "0",
    '"×" обязана закрыть панель, а не закрыть и тут же открыть её заново через focus()'
  );
  assert.equal(t.el.getAttribute("aria-expanded"), "false");

  unmount(t);
});

test("Escape закрывает немедленно — активный сигнал, гвардия его не касается", () => {
  const t = mountTrigger();
  click(t.el);
  assert.equal(panelEl().dataset.open, "1");

  dom.document.dispatchEvent(
    new dom.window.KeyboardEvent("keydown", { key: "Escape", bubbles: true })
  );
  assert.equal(panelEl().dataset.open, "0", "Esc обязан закрыть сразу после открытия");

  unmount(t);
});

test("клик вне триггера и панели — ПАССИВНЫЙ сигнал, не срабатывает сразу после открытия (DISMISS_GUARD_MS)", async () => {
  const t = mountTrigger();
  click(t.el);
  const panel = panelEl();
  assert.equal(panel.dataset.open, "1");

  // Тот же тап, которым открыли панель, у реальных сенсорных устройств
  // достраивает мышиные события, которые долетают уже ПОСЛЕ открытия —
  // это и защищает DISMISS_GUARD_MS (см. комментарий в builder_components.ex).
  dom.document.body.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  assert.equal(
    panel.dataset.open,
    "1",
    "пассивный клик мимо в первые доли секунды после открытия должен игнорироваться"
  );

  await delay(320); // > DISMISS_GUARD_MS (300мс)

  dom.document.body.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  assert.equal(
    panel.dataset.open,
    "0",
    "тот же пассивный клик мимо обязан закрыть панель после того, как гвардия истекла"
  );

  unmount(t);
});

// Задача 4.67: текст «Особенностей» шарда едет первой строкой блока шарда
// (`data-feat-notes` / `entry.notes`, сервер склеивает его с цитатами
// `siala_note`), а подпись над описанием Fandom у такого фита своя — у
// одиночного кружка её кладёт сервер в `data-label-vanilla`, у стопки она
// едет в записи фита (`entry.vanillaLabel`) и перекрывает общую подпись
// триггера только у этого фита.
function mountWith(dataset) {
  const el = dom.document.createElement("span");
  el.id = `feat-info-test-${nextId++}`;
  el.setAttribute("tabindex", "0");
  Object.assign(el.dataset, { labelClose: "Закрыть" }, dataset);
  dom.document.body.appendChild(el);
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();
  return { el, hook };
}

const texts = (root, selector) =>
  Array.from(root.querySelectorAll(selector)).map((node) => node.textContent);

test("одиночный кружок: текст шарда — в блоке шарда, над описанием Fandom — своя подпись", () => {
  const t = mountWith({
    featName: "Point blank shot",
    featDescription: "+1 within 15 feet",
    featChanged: "true",
    featNotes: JSON.stringify(["+5 до 5 метров"]),
    labelChanged: "Изменено на Сиале",
    labelChangedGeneric: "ОБЩЕЕ ПРЕДУПРЕЖДЕНИЕ",
    labelVanilla: "ЧИСЛА ВАНИЛЬНЫЕ",
  });
  click(t.el);
  const panel = panelEl();

  assert.deepEqual(texts(panel, ".feat-info-shard .feat-info-shard-note"), ["+5 до 5 метров"]);
  assert.deepEqual(texts(panel, ".feat-info-vanilla-label"), ["ЧИСЛА ВАНИЛЬНЫЕ"]);
  assert.ok(!panel.textContent.includes("ОБЩЕЕ ПРЕДУПРЕЖДЕНИЕ"), "есть текст — общего предупреждения нет");

  // Порядок: блок шарда → подпись → описание Fandom.
  const order = Array.from(panel.querySelectorAll(".feat-info-shard, .feat-info-vanilla-label, .feat-info-body"))
    .map((node) => node.className);
  assert.deepEqual(order, ["feat-info-shard", "feat-info-vanilla-label", "feat-info-body"]);

  unmount(t);
});

test("стопка: своя подпись над Fandom — только у фита, чья запись её несёт", () => {
  const t = mountWith({
    featEntries: JSON.stringify([
      { name: "Evasion", description: "vanilla A", changed: true, notes: ["заметка шарда"] },
      {
        name: "Imbue arrow",
        description: "vanilla B",
        changed: true,
        notes: ["10д6 (Максимум 35д6)"],
        vanillaLabel: "ЧИСЛА ВАНИЛЬНЫЕ",
      },
    ]),
    labelChanged: "Изменено на Сиале",
    labelChangedGeneric: "ОБЩЕЕ ПРЕДУПРЕЖДЕНИЕ",
    labelVanilla: "ВАНИЛЬНОЕ ОПИСАНИЕ",
  });
  t.el.setAttribute("aria-label", "Что дают фиты уровня 2");
  click(t.el);
  const [evasion, imbue] = Array.from(panelEl().querySelectorAll(".feat-info-entry"));

  assert.deepEqual(texts(evasion, ".feat-info-vanilla-label"), ["ВАНИЛЬНОЕ ОПИСАНИЕ"]);
  assert.deepEqual(texts(imbue, ".feat-info-vanilla-label"), ["ЧИСЛА ВАНИЛЬНЫЕ"]);
  assert.deepEqual(texts(imbue, ".feat-info-shard-note"), ["10д6 (Максимум 35д6)"]);

  unmount(t);
});

// Задача 4.71: фит шарда без страницы на Fandom — поп-ап рисует страницу шарда
// блоками (`data-feat-page` у одиночного кружка, `entry.page` у стопки) под
// своей подписью (`data-label-page`). Тег — из закрытого набора по `kind`,
// текст — только `textContent`: строка из данных разметкой не становится.
const PAGE = [
  { kind: "p", text: "Монах может совершить бросок." },
  { kind: "p", text: "Пометка: Использовать умение можно с 15 уровня Монаха." },
  { kind: "h", text: "Общие" },
  { kind: "ul", items: ["задержка в размере:"] },
  { kind: "pre", text: "27 - (лвл монка - 14) раундов" },
  { kind: "ol", items: ["Серпы", "Ручные топоры"] },
];

test("одиночный кружок: страница шарда блоками, под своей подписью, без описания Fandom", () => {
  const t = mountWith({
    featName: "Instinctive Throw",
    featChanged: "false",
    featPage: JSON.stringify(PAGE),
    labelPage: "ТЕКСТ ШАРДА",
  });
  click(t.el);
  const panel = panelEl();

  assert.deepEqual(texts(panel, ".feat-info-vanilla-label"), ["ТЕКСТ ШАРДА"]);
  assert.deepEqual(texts(panel, ".feat-info-page > .feat-info-body"), [
    "Монах может совершить бросок.",
    "Пометка: Использовать умение можно с 15 уровня Монаха.",
  ]);
  assert.deepEqual(texts(panel, ".feat-info-page-h"), ["Общие"]);
  assert.deepEqual(texts(panel, "ul.feat-info-page-list > li"), ["задержка в размере:"]);
  assert.deepEqual(texts(panel, "ol.feat-info-page-list > li"), ["Серпы", "Ручные топоры"]);
  assert.deepEqual(texts(panel, ".feat-info-page-pre"), ["27 - (лвл монка - 14) раундов"]);

  // Порядок блоков — как на странице.
  const order = Array.from(panel.querySelector(".feat-info-page").children).map((node) => node.tagName);
  assert.deepEqual(order, ["P", "P", "P", "UL", "P", "OL"]);

  // Ни пустого абзаца описания, ни блока «изменено на Сиале», ни ссылки.
  assert.equal(panel.querySelectorAll(".feat-info-scroll > .feat-info-body").length, 0);
  assert.equal(panel.querySelectorAll(".feat-info-shard").length, 0);
  assert.equal(panel.querySelectorAll("a").length, 0);

  unmount(t);
});

// 🔴 Безопасность: враждебные строки — в тексте, в пунктах списка и даже
// в поле `kind` — остаются текстом. Ни `<img>`, ни `<script>`, ни ссылки
// в панели не появляется; строка видна буквально.
test("враждебная разметка в блоках страницы — текст, а не HTML", () => {
  const hostile = [
    { kind: "p", text: '<img src=x onerror="globalThis.__pwned = 1">' },
    { kind: "ul", items: ["<script>globalThis.__pwned = 2</script>", "[javascript:alert(3) click]"] },
    { kind: '<img src=x onerror="globalThis.__pwned = 3">', text: "<b>жирный</b>" },
    { kind: "pre", text: "</p><a href=\"javascript:alert(4)\">x</a>" },
  ];
  const t = mountWith({
    featName: "Hostile",
    featChanged: "false",
    featPage: JSON.stringify(hostile),
    labelPage: "ТЕКСТ ШАРДА",
  });
  click(t.el);
  const panel = panelEl();

  assert.equal(panel.querySelectorAll("img, script, b, a").length, 0);
  assert.equal(globalThis.__pwned, undefined);
  assert.ok(panel.textContent.includes('<img src=x onerror="globalThis.__pwned = 1">'));
  assert.ok(panel.textContent.includes("<script>globalThis.__pwned = 2</script>"));
  assert.ok(panel.textContent.includes("[javascript:alert(3) click]"));
  assert.ok(panel.textContent.includes("<b>жирный</b>"));

  // Контроль измерителя: тот же запрос находит теги, когда они настоящие.
  const probe = dom.document.createElement("div");
  probe.innerHTML = "<b>x</b><a href='#'>y</a>";
  assert.equal(probe.querySelectorAll("img, script, b, a").length, 2);

  unmount(t);
});

test("битый JSON страницы — пустая страница, а не исключение", () => {
  const t = mountWith({
    featName: "Broken",
    featChanged: "false",
    featPage: "{not json",
    labelPage: "ТЕКСТ ШАРДА",
  });
  click(t.el);
  const panel = panelEl();
  assert.equal(panel.dataset.open, "1");
  assert.equal(panel.querySelectorAll(".feat-info-page").length, 0);
  unmount(t);
});

test("стопка: страница — в записи фита шарда, описание Fandom — у соседа", () => {
  const t = mountWith({
    featEntries: JSON.stringify([
      { name: "Instinctive Throw", description: null, changed: false, notes: [], page: PAGE },
      { name: "Deflect arrows", description: "vanilla A", changed: false, notes: [] },
    ]),
    labelPage: "ТЕКСТ ШАРДА",
  });
  t.el.setAttribute("aria-label", "Что дают фиты уровня 5");
  click(t.el);
  const [throwEntry, deflect] = Array.from(panelEl().querySelectorAll(".feat-info-entry"));

  assert.deepEqual(texts(throwEntry, ".feat-info-vanilla-label"), ["ТЕКСТ ШАРДА"]);
  assert.deepEqual(texts(throwEntry, ".feat-info-page-h"), ["Общие"]);
  assert.equal(throwEntry.querySelectorAll(":scope > .feat-info-body").length, 0);

  assert.equal(deflect.querySelectorAll(".feat-info-page").length, 0);
  assert.deepEqual(texts(deflect, ":scope > .feat-info-body"), ["vanilla A"]);
  assert.deepEqual(texts(deflect, ".feat-info-vanilla-label"), []);

  unmount(t);
});
