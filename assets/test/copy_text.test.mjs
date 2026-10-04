// Regression test for `.CopyText` (`BuildCalculatorWeb.BuilderComponents`,
// `copy_text/1`) — task 3.179's coordinator follow-up. This ONE hook now
// backs both the view screen's own copy button (`#copy-text`, moved off its
// former locally-defined `.CopyText`) and the constructor's brand new one
// (`#export-copy`) — the same reasoning `download_text.test.mjs` documents
// for the sibling hook (CLAUDE.md §9: two copies of one rule have drifted
// apart in this project four times in three days).
//
// The behaviour under test: the SAME hook reads a `<pre>` (`.textContent`)
// or a `<textarea>` (`.value`) through one accessor, the label lives in its
// own `.btn-label` span so a future icon sitting next to it survives the
// "Скопировано" swap, a second click inside the 1400ms window does not
// freeze the label on "Скопировано" forever, and the Clipboard-API fallback
// actually copies `text` — through a throwaway `<textarea>` it selects
// itself — rather than reporting success while copying whatever (if
// anything) happened to be selected on the page already.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderComponents.CopyText";

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

function mountSource(tag, content) {
  const src = dom.document.createElement(tag);
  src.id = `cp-src-${nextId++}`;
  if (tag === "textarea") {
    src.value = content;
  } else {
    src.textContent = content;
  }
  dom.document.body.appendChild(src);
  return src;
}

// Разметка ровно та, что рендерит `copy_text/1`: подпись — отдельный
// `<span class="btn-label">`, а не текстовый узел прямо внутри кнопки.
function mountButton(src, { label = "Скопировать текст", labelCopied = "Скопировано" } = {}) {
  const el = dom.document.createElement("button");
  el.id = `cp-btn-${nextId++}`;
  el.dataset.target = `#${src.id}`;
  el.dataset.labelCopied = labelCopied;

  const span = dom.document.createElement("span");
  span.className = "btn-label";
  span.textContent = label;
  el.appendChild(span);

  dom.document.body.appendChild(el);
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();
  return { el, hook, span };
}

function click(el) {
  el.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
}

function stubClipboardSuccess() {
  const calls = [];
  const original = dom.window.navigator.clipboard.writeText;
  dom.window.navigator.clipboard.writeText = (text) => {
    calls.push(text);
    return Promise.resolve();
  };
  return {
    calls,
    restore() {
      dom.window.navigator.clipboard.writeText = original;
    }
  };
}

function stubClipboardFailure() {
  const original = dom.window.navigator.clipboard.writeText;
  dom.window.navigator.clipboard.writeText = () => Promise.reject(new Error("denied"));
  return {
    restore() {
      dom.window.navigator.clipboard.writeText = original;
    }
  };
}

// happy-dom не реализует `document.execCommand` вовсе (проверено вживую) —
// хук зовёт его только на фолбэке, поэтому стаб заводится ТОЛЬКО в тестах
// фолбэка, а не глобально в `before()`: тест счастливого пути обязан пройти
// и без него, иначе он держится на постороннем стабе, а не на самом хуке.
//
// Перехватывает и создание временной `<textarea>` (`document.createElement`,
// тем же приёмом, что `download_text.test.mjs`'s `spyOnDownload`), и сам
// вызов `execCommand` — чтобы проверить не «вызвали ли», а «было ли ЧТО
// копировать»: чьё это значение, выделено ли оно целиком, и была ли
// временная `<textarea>` вообще присоединена к документу в момент вызова
// (execCommand не может скопировать то, что не в рендер-дереве).
function spyOnFallbackCopy() {
  const originalCreateElement = dom.document.createElement.bind(dom.document);
  const hadExecCommand = "execCommand" in dom.document;
  const originalExecCommand = dom.document.execCommand;

  let createdTextarea = null;
  let call = null;

  dom.document.createElement = (tag) => {
    const node = originalCreateElement(tag);
    if (tag === "textarea") createdTextarea = node;
    return node;
  };

  dom.document.execCommand = (cmd) => {
    call = {
      cmd,
      attachedToBody: createdTextarea ? dom.document.body.contains(createdTextarea) : false,
      value: createdTextarea ? createdTextarea.value : null,
      selectionStart: createdTextarea ? createdTextarea.selectionStart : null,
      selectionEnd: createdTextarea ? createdTextarea.selectionEnd : null
    };
    return true;
  };

  return {
    textarea: () => createdTextarea,
    call: () => call,
    restore() {
      dom.document.createElement = originalCreateElement;
      if (hadExecCommand) {
        dom.document.execCommand = originalExecCommand;
      } else {
        delete dom.document.execCommand;
      }
    }
  };
}

test("<pre> (диалог конструктора) — копирует textContent, подпись временно меняется и возвращается", async () => {
  const src = mountSource("pre", "весь текст билда");
  const t = mountButton(src);
  const clipboard = stubClipboardSuccess();

  click(t.el);
  await delay(0); // дать async-обработчику долистать до `await`

  assert.deepEqual(clipboard.calls, ["весь текст билда"]);
  assert.equal(t.span.textContent, "Скопировано");

  await delay(1450); // > 1400мс таймера возврата подписи
  assert.equal(t.span.textContent, "Скопировать текст");

  clipboard.restore();
});

test("<textarea> (экран просмотра) — читает value, а не textContent", async () => {
  const src = mountSource("textarea", "билд из textarea");
  src.appendChild(dom.document.createTextNode("не это"));
  const t = mountButton(src);
  const clipboard = stubClipboardSuccess();

  click(t.el);
  await delay(0);

  assert.deepEqual(clipboard.calls, ["билд из textarea"]);
  clipboard.restore();
});

// 🔴 Дефект 1 (найден чтением координатором): второй клик внутри окна
// первого таймера раньше запоминал уже подменённое "Скопировано" как `was`,
// и после ДВУХ таймеров подпись застревала на "Скопировано" навсегда —
// вместо того чтобы вернуться к исходной. Таймлайн: клик1 при t=0 (таймер
// T1 → t=1400), клик2 при t=500 (обязан СНЯТЬ T1, поставить T2 → t=1900).
// Если T1 не снят — на t≈1450 подпись уже вернулась бы преждевременно, ДО
// того как истекло окно от второго клика. Если `was` неверный — на t≈1950
// подпись останется "Скопировано", а не вернётся к исходной.
test("два клика подряд внутри 1400мс не заклинивают подпись на «Скопировано»", async () => {
  const src = mountSource("pre", "текст");
  const t = mountButton(src);
  const clipboard = stubClipboardSuccess();

  click(t.el); // t=0, таймер T1 → сработал бы на t=1400
  await delay(0);
  assert.equal(t.span.textContent, "Скопировано");

  await delay(500); // t≈500
  click(t.el); // клик2 обязан снять T1 и поставить T2 → t≈1900
  await delay(0);
  assert.equal(t.span.textContent, "Скопировано");

  await delay(950); // t≈1450 — T1, если бы уцелел, уже сработал бы здесь
  assert.equal(
    t.span.textContent,
    "Скопировано",
    "второй клик обязан был снять первый таймер — иначе тут уже вернулось бы исходное раньше срока"
  );

  await delay(500); // t≈1950 — T2 (от второго клика) уже должен был сработать
  assert.equal(
    t.span.textContent,
    "Скопировать текст",
    "после обоих таймеров подпись обязана вернуться к ИСХОДНОЙ, а не застрять на «Скопировано»"
  );

  clipboard.restore();
});

test("destroyed() снимает ожидающий таймер — он не пишет в подпись задним числом", async () => {
  const src = mountSource("pre", "текст");
  const t = mountButton(src);
  const clipboard = stubClipboardSuccess();

  click(t.el);
  await delay(0);
  assert.equal(t.span.textContent, "Скопировано");

  assert.doesNotThrow(() => t.hook.destroyed());

  await delay(1450); // > 1400мс — таймер, если бы уцелел, сработал бы здесь
  assert.equal(
    t.span.textContent,
    "Скопировано",
    "снятый в destroyed() таймер не имеет права позже переписать подпись"
  );

  clipboard.restore();
});

// Ловушка, которую координатор попросил закрыть тестом ДО прихода иконки:
// хук трогает `.btn-label`, а не `this.el.textContent`, поэтому сосед
// подписи (будущая иконка) не пропадает при подмене на "Скопировано".
test("значок рядом с подписью переживает клик — хук трогает только .btn-label (и после клика, и после таймаута)", async () => {
  const src = mountSource("pre", "текст");
  const t = mountButton(src);
  const icon = dom.document.createElement("i");
  icon.className = "icon";
  t.el.insertBefore(icon, t.span);
  const clipboard = stubClipboardSuccess();

  click(t.el);
  await delay(0);

  // Сразу после клика: подпись подменена, значок — ещё ребёнок кнопки.
  assert.equal(t.span.textContent, "Скопировано");
  assert.equal(icon.parentNode, t.el, "иконка обязана остаться ребёнком кнопки сразу после клика");
  assert.equal(t.el.contains(icon), true, "иконка не должна исчезнуть при подмене подписи");

  await delay(1450); // > 1400мс таймера возврата подписи

  // И после таймаута: подпись вернулась, значок по-прежнему на месте — было
  // ровно то, что попросил закрыть тестом координатор ДО прихода иконки от
  // designer: `textContent =` на самой кнопке снёс бы значок безвозвратно
  // уже на первом клике, а это разошлось бы только на живом клике мышью.
  assert.equal(t.span.textContent, "Скопировать текст");
  assert.equal(icon.parentNode, t.el, "иконка обязана остаться ребёнком кнопки и после возврата подписи");
  assert.equal(t.el.contains(icon), true, "иконка не должна исчезнуть и после таймаута");

  clipboard.restore();
});

// 🔴 Дефект 2 (найден чтением координатором): раньше фолбэк звал
// `execCommand("copy")` без единого выделения для источников без `.select()`
// (`<pre>`) — подпись врала об успехе, копируя то, что игрок случайно
// выделил на странице, или ничего. Проверяем НАБЛЮДАЕМОЕ, а не факт вызова:
// куда делся `text`, выделен ли он целиком, и был ли элемент вообще
// присоединён к документу в момент вызова.
test("Clipboard API отказал, источник — <pre>: фолбэк копирует ЧЕРЕЗ временную textarea с live-выделением", async () => {
  const src = mountSource("pre", "текст без select");
  const t = mountButton(src);
  const clipboard = stubClipboardFailure();
  const spy = spyOnFallbackCopy();

  assert.equal(typeof src.select, "undefined", "у <pre> select() не существует вовсе — фолбэк не должен его звать");

  await assert.doesNotReject(async () => {
    click(t.el);
    await delay(0);
  });

  const call = spy.call();
  assert.ok(call, "execCommand обязан быть вызван");
  assert.equal(call.cmd, "copy");
  assert.equal(call.value, "текст без select", "копируем ИМЕННО наш текст, а не что попало");
  assert.equal(call.attachedToBody, true, "временная textarea обязана быть в документе в момент copy");
  assert.equal(call.selectionStart, 0);
  assert.equal(call.selectionEnd, "текст без select".length, "выделение обязано покрывать ВЕСЬ текст");

  // Уборка: временная textarea не остаётся мусором в документе.
  assert.equal(dom.document.body.contains(spy.textarea()), false);

  assert.equal(t.span.textContent, "Скопировано", "фолбэк тоже обязан подтвердить копирование");

  clipboard.restore();
  spy.restore();
});

test("Clipboard API отказал, источник — <textarea>: та же временная textarea, тот же live-выделенный текст", async () => {
  const src = mountSource("textarea", "текст из textarea для фолбэка");
  const t = mountButton(src);
  const clipboard = stubClipboardFailure();
  const spy = spyOnFallbackCopy();

  click(t.el);
  await delay(0);

  const call = spy.call();
  assert.equal(call.cmd, "copy");
  assert.equal(call.value, "текст из textarea для фолбэка");
  assert.equal(call.attachedToBody, true);
  assert.equal(call.selectionStart, 0);
  assert.equal(call.selectionEnd, "текст из textarea для фолбэка".length);
  // Копия идёт через СВОЮ временную textarea, не через `src` — исходный
  // элемент фолбэк вообще не трогает, поэтому его собственное выделение
  // (если было) остаётся нетронутым.
  assert.notEqual(spy.textarea(), src, "фолбэк обязан создать СВОЮ textarea, а не выделять исходный <textarea>");

  clipboard.restore();
  spy.restore();
});

test("отсутствующая цель — клик ничего не делает и не падает", async () => {
  const el = dom.document.createElement("button");
  el.id = `cp-btn-${nextId++}`;
  el.dataset.target = "#does-not-exist";
  el.dataset.labelCopied = "Скопировано";
  const span = dom.document.createElement("span");
  span.className = "btn-label";
  span.textContent = "Скопировать текст";
  el.appendChild(span);
  dom.document.body.appendChild(el);
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();

  const clipboard = stubClipboardSuccess();
  await assert.doesNotReject(async () => {
    click(el);
    await delay(0);
  });
  assert.deepEqual(clipboard.calls, []);
  assert.equal(span.textContent, "Скопировать текст", "подпись не трогается без цели");

  clipboard.restore();
});
