// Regression test for `.ModalFocus` (`BuildCalculatorWeb.BuilderComponents`,
// `modal_scrim/1`) — task 4.40, item 8. Before it, none of the four modal
// windows (export and the game-log import in the builder, the vanilla text
// import, the canonical text on the view screen) touched focus: measured in
// Chrome with real keys, focus stayed on the opener UNDER the scrim, Tab and
// Shift+Tab walked the page behind the window, and "Close" dropped focus on
// `<body>`.
//
// The hook reacts to the `hidden` attribute the server renders (it has no
// events of its own), so every test drives it the way LiveView does: toggle
// `hidden`, then call `updated()`. The DOM mirrors `modal_scrim/1` plus the
// `.modal` the call sites put inside it.
//
// happy-dom computes no layout: `getClientRects()` and `checkVisibility()`
// answer "visible" for everything there. The hook therefore checks `[hidden]`
// and a closed `<details>` explicitly — the same checks Chrome runs through —
// and these tests cover exactly those.
import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderComponents.ModalFocus";

let dom;
let hookDefinition;

before(async () => {
  dom = installDom({ width: 1440, height: 900 });
  hookDefinition = await loadHook(HOOK_NAME);
});

after(() => {
  uninstallDom();
});

let hooks = [];

beforeEach(() => {
  for (const h of hooks) h.destroyed();
  hooks = [];
  dom.document.body.replaceChildren();
});

// Страница: кнопка-открывашка и ещё одна кнопка ДО окна, кнопка ПОСЛЕ окна;
// в окне — «Закрыть», поле, две кнопки, затем свёрнутый `<details>` с кнопкой
// внутри, спрятанная кнопка и выключенная кнопка. Три последних стоят В КОНЦЕ
// нарочно: сочти хук хоть одну из них достижимой — «последний» элемент окна
// сдвинется, и перенос Tab с последнего на первый сломается.
function mountPage() {
  const d = dom.document;
  d.body.innerHTML = `
    <button id="before">before</button>
    <button id="opener">Export…</button>
    <div class="scrim" id="dlg" hidden data-opener="#opener">
      <div class="modal" role="dialog" aria-modal="true">
        <div class="modal-head"><h2>Title</h2><button id="close">Close</button></div>
        <textarea id="text"></textarea>
        <button id="parse">Read</button>
        <button id="apply">Apply</button>
        <details id="more"><summary id="sum">Not ours</summary><button id="inside-details">x</button></details>
        <button id="hidden-btn" hidden>hidden</button>
        <button id="off" disabled>off</button>
      </div>
    </div>
    <button id="after">after</button>`;
  const el = d.getElementById("dlg");
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();
  hooks.push(hook);
  return { el, hook, $: (id) => d.getElementById(id) };
}

function open(page) {
  page.el.removeAttribute("hidden");
  page.hook.updated();
}

function close(page) {
  page.el.setAttribute("hidden", "");
  page.hook.updated();
}

function tab(target, shift = false) {
  const ev = new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    shiftKey: shift,
    bubbles: true,
    cancelable: true
  });
  target.dispatchEvent(ev);
  return ev;
}

test("открытие уводит фокус на первый элемент окна, закрытие возвращает его на открывашку", () => {
  const page = mountPage();
  page.$("opener").focus();

  open(page);
  assert.equal(dom.document.activeElement.id, "close");

  close(page);
  assert.equal(dom.document.activeElement.id, "opener");
});

test("Tab с последнего элемента — на первый, Shift+Tab с первого — на последний", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);

  // Последний достижимый — `<summary>` свёрнутого списка: кнопка внутри него,
  // спрятанная и выключенная кнопки в счёт не идут.
  page.$("sum").focus();
  const forward = tab(page.$("sum"));
  assert.equal(forward.defaultPrevented, true);
  assert.equal(dom.document.activeElement.id, "close");

  const backward = tab(page.$("close"), true);
  assert.equal(backward.defaultPrevented, true);
  assert.equal(dom.document.activeElement.id, "sum");
});

test("в середине окна Tab не перехватывается — ходит браузер", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);

  page.$("text").focus();
  assert.equal(tab(page.$("text")).defaultPrevented, false);
  assert.equal(tab(page.$("parse"), true).defaultPrevented, false);
});

test("раскрытый `<details>` отдаёт свою кнопку в обход, свёрнутый — нет", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);

  // Свёрнут: последний — `<summary>`, с него Tab переносится на первый.
  page.$("sum").focus();
  assert.equal(tab(page.$("sum")).defaultPrevented, true);
  assert.equal(dom.document.activeElement.id, "close");

  // Раскрыт: кнопка внутри стала достижимой и последней — с `<summary>` Tab
  // ходит браузером, перенос — уже с неё.
  page.$("more").setAttribute("open", "");
  page.$("sum").focus();
  assert.equal(tab(page.$("sum")).defaultPrevented, false);
  page.$("inside-details").focus();
  assert.equal(tab(page.$("inside-details")).defaultPrevented, true);
  assert.equal(dom.document.activeElement.id, "close");
  tab(page.$("close"), true);
  assert.equal(dom.document.activeElement.id, "inside-details");
});

test("фокус, ушедший за открытое окно, возвращается в окно", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);

  page.$("after").focus();
  assert.equal(dom.document.activeElement.id, "close");
});

test("закрытое окно фокус не трогает: ни Tab, ни уход фокуса", () => {
  const page = mountPage();
  page.$("before").focus();

  assert.equal(tab(page.$("before")).defaultPrevented, false);
  page.$("after").focus();
  assert.equal(dom.document.activeElement.id, "after");
});

test("открыли без фокуса на кнопке (Safari по клику не фокусирует) — возврат на `data-opener`", () => {
  const page = mountPage();
  dom.document.activeElement?.blur?.();
  assert.equal(dom.document.activeElement, dom.document.body);

  open(page);
  assert.equal(dom.document.activeElement.id, "close");

  close(page);
  assert.equal(dom.document.activeElement.id, "opener");
});

test("закрытие не отнимает фокус, который увели за окно нарочно", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);

  // Сначала окно закрывается (сервер дорисовал `hidden`), потом фокус уводят
  // на другой элемент страницы, и только потом приходит `updated()`.
  page.el.setAttribute("hidden", "");
  page.$("before").focus();
  page.hook.updated();
  assert.equal(dom.document.activeElement.id, "before");
});

test("снятый хук больше не держит фокус", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);

  page.hook.destroyed();
  hooks = hooks.filter((h) => h !== page.hook);
  page.$("after").focus();
  assert.equal(dom.document.activeElement.id, "after");
});

test("фокус возвращается туда, откуда открыли, даже если это не `data-opener`", () => {
  const page = mountPage();
  page.$("before").focus();

  open(page);
  close(page);
  assert.equal(dom.document.activeElement.id, "before");
});

// После закрытия окно молчит дважды: `isOpen()` и сам `hidden` (всё внутри
// спрятанного затемнения недостижимо, возвращать фокус некуда).
test("после закрытия уход фокуса по странице хук не замечает", () => {
  const page = mountPage();
  page.$("opener").focus();
  open(page);
  close(page);

  page.$("after").focus();
  assert.equal(dom.document.activeElement.id, "after");
});
