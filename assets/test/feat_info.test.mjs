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
