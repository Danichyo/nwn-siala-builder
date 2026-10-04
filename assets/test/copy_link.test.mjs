// `.CopyLink` (`builder_live.html.heex`: `#copy-link`, `#copy-short-link`) —
// task 4.3. The "copied" label used to be a Russian string literal inside the
// hook, so the English edition would have printed «Скопировано» on click:
// a string in JS never goes through gettext. It now comes from the button's
// own `data-label-copied`, which the template fills with `gettext("Copied")`
// — the same contract `.CopyText` (`copy_text/1`) already had.
//
// What is checked is the RESULT, not the call (HANDOFF.md, "Тест может
// закреплять дефект"): the label the player sees is the attribute's value,
// in whichever language it came, and the original label comes back.
//
// ⚠️ Not covered on purpose: a second click inside the 1400ms window still
// captures the swapped label as `was` — the known `.CopyLink` defect
// HANDOFF.md names under 3.179. 4.3 did not touch it.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { setTimeout as delay } from "node:timers/promises";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderLive.CopyLink";

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

// Разметка та же, что у `#copy-link`: видимый `<input readonly>` со ссылкой
// и кнопка, у которой подпись — её собственный текст.
function mount({ url, label, labelCopied }) {
  const input = dom.document.createElement("input");
  input.id = `cl-src-${nextId++}`;
  input.value = url;
  dom.document.body.appendChild(input);

  const el = dom.document.createElement("button");
  el.id = `cl-btn-${nextId++}`;
  el.dataset.target = `#${input.id}`;
  el.dataset.labelCopied = labelCopied;
  el.textContent = label;
  dom.document.body.appendChild(el);

  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();
  return el;
}

function stubClipboard() {
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

function click(el) {
  el.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
}

for (const [label, labelCopied] of [
  ["Copy link", "Copied"],
  ["Скопировать ссылку", "Скопировано"]
]) {
  test(`подпись «скопировано» берётся из data-label-copied: ${labelCopied}`, async () => {
    const el = mount({ url: "http://localhost/b/abc", label, labelCopied });
    const clipboard = stubClipboard();

    click(el);
    await delay(0); // дать async-обработчику долистать до `await`

    assert.deepEqual(clipboard.calls, ["http://localhost/b/abc"]);
    assert.equal(el.textContent, labelCopied);

    await delay(1450); // > 1400мс таймера возврата подписи
    assert.equal(el.textContent, label);

    clipboard.restore();
  });
}
