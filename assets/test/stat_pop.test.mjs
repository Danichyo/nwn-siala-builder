// Regression test for `.StatPop` (`BuildCalculatorWeb.BuilderComponents`,
// `stat_pop/1`) — the "breakdown" toggletip on totals-panel numbers
// (CLAUDE.md §6, task 3.13). The behaviour under test: below the 940px
// breakpoint the hook must never attach a single listener or ever turn the
// inert `data-pop-*` attributes into visible markup — "hidden by CSS" is
// explicitly the wrong shape here (AGENT_QUEUE.md 3.138 П1) — and the
// decision has to be re-made on every LIVE resize across the threshold, not
// only once at mount (see the hook's own comment on `applyMode()`).
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderComponents.StatPop";
const BREAKPOINT_PX = 940; // must match `matchMedia("(max-width: 940px)")` in the hook

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
  const id = `stat-pop-test-${nextId++}`;
  el.id = `stat-pop-${id}`;
  el.dataset.popTitle = "AB";
  el.dataset.popTerms = JSON.stringify([{ label: "BAB", value: "20" }]);
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
  return dom.document.getElementById("stat-pop-panel");
}

test("ниже 940px хук НЕ вешает слушателей: role/tabindex не появляются, клик ничего не открывает", () => {
  dom.window.happyDOM.setViewport({ width: BREAKPOINT_PX - 1 });
  const t = mountTrigger();

  assert.equal(t.el.getAttribute("role"), null, "role не должен появиться ниже порога");
  assert.equal(t.el.getAttribute("tabindex"), null);
  assert.equal(t.el.classList.contains("stat-pop-ready"), false);

  click(t.el);
  const panel = panelEl();
  assert.ok(
    panel === null || panel.dataset.open !== "1",
    "клик по неактивному триггеру не должен открыть панель — разбор не существует как разметка, а не спрятан CSS-ом"
  );

  unmount(t);
});

test("выше 940px хук включается: role, tabindex, клик открывает разбор", () => {
  dom.window.happyDOM.setViewport({ width: BREAKPOINT_PX + 1 });
  const t = mountTrigger();

  assert.equal(t.el.getAttribute("role"), "button");
  assert.equal(t.el.getAttribute("tabindex"), "0");
  assert.ok(t.el.classList.contains("stat-pop-ready"));

  click(t.el);
  const panel = panelEl();
  assert.equal(panel.dataset.open, "1");
  const terms = panel.querySelectorAll(".stat-pop-term");
  assert.equal(terms.length, 1);
  assert.ok(panel.textContent.includes("BAB"));

  unmount(t);
});

test("порог применяется заново на КАЖДОМ живом ресайзе, не только при первой загрузке", () => {
  dom.window.happyDOM.setViewport({ width: BREAKPOINT_PX + 1 });
  const t = mountTrigger();
  assert.equal(t.el.getAttribute("role"), "button", "выше порога — включён при монтировании");

  dom.window.happyDOM.setViewport({ width: BREAKPOINT_PX - 1 }); // живой переход вниз
  assert.equal(t.el.getAttribute("role"), null, "живой ресайз вниз обязан выключить хук");

  dom.window.happyDOM.setViewport({ width: BREAKPOINT_PX + 1 }); // и обратно вверх
  assert.equal(t.el.getAttribute("role"), "button", "и живой ресайз вверх обязан включить обратно");

  unmount(t);
});
