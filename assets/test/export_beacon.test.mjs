// `.ExportBeacon` (`BuildCalculatorWeb.BuilderComponents`, `download_text/1`,
// задача 4.54) — маяк счётчика «экспорт скачан». Пустой скрытый элемент рядом
// с кнопкой «скачать .txt»: сигнал `bc:downloaded` ему подаёт `.DownloadText`,
// а он шлёт серверу одно имя события, без текста и имени файла. Отдельным
// элементом, а не самой кнопкой: `pushEvent` метит свой элемент
// `data-phx-ref-src` (HANDOFF.md, «хук-отправитель»).
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderComponents.ExportBeacon";

let dom;
let hookDefinition;

before(async () => {
  dom = installDom({ width: 1440, height: 900 });
  hookDefinition = await loadHook(HOOK_NAME);
});

after(() => {
  uninstallDom();
});

function mountBeacon() {
  const el = dom.document.createElement("span");
  el.id = "export-download-analytics";
  el.hidden = true;
  dom.document.body.appendChild(el);
  const pushed = [];
  const hook = instantiateHook(hookDefinition, el);
  hook.pushEvent = (event, payload, onReply) => pushed.push({ event, payload, onReply });
  hook.mounted();
  return { el, hook, pushed };
}

test("сигнал bc:downloaded — одно событие серверу, без данных", () => {
  const { el, pushed } = mountBeacon();

  el.dispatchEvent(new dom.window.CustomEvent("bc:downloaded"));

  assert.equal(pushed.length, 1);
  assert.equal(pushed[0].event, "analytics_export_downloaded");
  assert.deepEqual(pushed[0].payload, {});
  // С колбэком ответа LiveView глотает ошибку отправки (нет связи) сам —
  // без него отказ стал бы необработанным Promise в консоли.
  assert.equal(typeof pushed[0].onReply, "function");
});

test("чужие события и клики маяк не слушает", () => {
  const { el, pushed } = mountBeacon();

  el.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
  el.dispatchEvent(new dom.window.CustomEvent("bc:other"));

  assert.equal(pushed.length, 0);
});

test("снятый маяк больше не шлёт", () => {
  const { el, hook, pushed } = mountBeacon();

  hook.destroyed();
  el.dispatchEvent(new dom.window.CustomEvent("bc:downloaded"));

  assert.equal(pushed.length, 0);
});
