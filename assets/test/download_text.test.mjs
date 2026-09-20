// Regression test for `.DownloadText` (`BuildCalculatorWeb.BuilderComponents`,
// `download_text/1`) — the "download build as .txt" button (task 3.179). The
// hook is deliberately dumb: read whatever `data-target` already holds and
// hand it, unchanged, to the browser's download machinery — no `pushEvent`
// (CLAUDE.md §6, bug 1.11), no text assembled client-side, no second
// `data-*` the hook stitches on (the component's own moduledoc: a future
// share-link suffix belongs entirely on the server, never here).
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { installDom, uninstallDom } from "./support/dom.mjs";
import { loadHook } from "./support/hooks.mjs";
import { instantiateHook } from "./support/hook_instance.mjs";

const HOOK_NAME = "BuildCalculatorWeb.BuilderComponents.DownloadText";

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
  src.id = `dl-src-${nextId++}`;
  if (tag === "textarea") {
    src.value = content;
  } else {
    src.textContent = content;
  }
  dom.document.body.appendChild(src);
  return src;
}

function mountButton(src, filename) {
  const el = dom.document.createElement("button");
  el.id = `dl-btn-${nextId++}`;
  el.dataset.target = `#${src.id}`;
  el.dataset.filename = filename;
  dom.document.body.appendChild(el);
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();
  return { el, hook };
}

function click(el) {
  el.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }));
}

// Перехватываем ровно то, что снаружи наблюдаемо — какой Blob ушёл в
// `URL.createObjectURL`, по какому якорю кликнули и с каким `download`, и
// что тот же самый URL позже отозван, — а не внутренности хука. Node's own
// globals (`Blob`, `URL`) остаются настоящими; подменяются только два
// статических метода `URL`, которые иначе дёрнули бы реальный браузерный
// API, которого в happy-dom нет.
function spyOnDownload() {
  const originalCreateObjectURL = URL.createObjectURL;
  const originalRevokeObjectURL = URL.revokeObjectURL;
  const originalCreateElement = dom.document.createElement.bind(dom.document);

  const created = [];
  const revoked = [];
  let clickedAnchor = null;

  URL.createObjectURL = (blob) => {
    const url = `blob:mock-${created.length}`;
    created.push({ blob, url });
    return url;
  };
  URL.revokeObjectURL = (url) => revoked.push(url);

  dom.document.createElement = (tag) => {
    const node = originalCreateElement(tag);
    if (tag === "a") {
      const originalClick = node.click.bind(node);
      // Захватываем href/download РОВНО в момент клика — то самое "кликнули
      // по якорю с правильным download", а не просто "создали узел".
      node.click = () => {
        clickedAnchor = { href: node.href, download: node.download };
        originalClick();
      };
    }
    return node;
  };

  return {
    created,
    revoked,
    anchor: () => clickedAnchor,
    restore() {
      URL.createObjectURL = originalCreateObjectURL;
      URL.revokeObjectURL = originalRevokeObjectURL;
      dom.document.createElement = originalCreateElement;
    }
  };
}

test("источник <pre> (диалог конструктора) — читает textContent", async () => {
  const src = mountSource("pre", "build text goes here");
  const t = mountButton(src, "lvl5_fighter_5.txt");
  const spy = spyOnDownload();

  click(t.el);

  assert.equal(spy.created.length, 1, "должен уйти ровно один Blob в createObjectURL");
  const text = await spy.created[0].blob.text();
  assert.equal(text, "build text goes here");
  assert.equal(spy.created[0].blob.type, "text/plain;charset=utf-8");

  const anchor = spy.anchor();
  assert.ok(anchor, "должны были кликнуть по якорю");
  assert.equal(anchor.download, "lvl5_fighter_5.txt");

  // Отзыв — отложенный (`setTimeout(…, 0)`), не синхронный.
  assert.equal(spy.revoked.length, 0, "revokeObjectURL не должен звать СИНХРОННО");
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert.deepEqual(spy.revoked, [spy.created[0].url]);

  spy.restore();
});

test("источник <textarea> (экран просмотра) — читает value, а не textContent", async () => {
  const src = mountSource("textarea", "build text from a hidden textarea");
  // На всякий случай убеждаемся, что у элемента есть постороннее textContent,
  // не совпадающее с value — иначе тест не отличил бы правильный аксессор от
  // случайно верного.
  src.appendChild(dom.document.createTextNode("не это"));
  const t = mountButton(src, "lvl10_dwarven_defender_10.txt");
  const spy = spyOnDownload();

  click(t.el);

  const text = await spy.created[0].blob.text();
  assert.equal(text, "build text from a hidden textarea");
  assert.equal(spy.anchor().download, "lvl10_dwarven_defender_10.txt");

  spy.restore();
});

test("имя файла берётся из data-filename, не выдумывается заново на каждый клик", async () => {
  const src = mountSource("pre", "текст");
  const t = mountButton(src, "lvl1_fighter_1.txt");
  const spy = spyOnDownload();

  click(t.el);
  assert.equal(spy.anchor().download, "lvl1_fighter_1.txt");

  // Сервер поменял атрибут (LiveView сам обновил бы его диффом на новый
  // рендер) — второй клик обязан взять уже новое значение, а не то, что
  // было при монтировании хука.
  t.el.dataset.filename = "lvl2_fighter_2.txt";
  click(t.el);
  assert.equal(spy.anchor().download, "lvl2_fighter_2.txt");

  spy.restore();
});

test("отсутствующая цель — клик ничего не скачивает и не падает", () => {
  const el = dom.document.createElement("button");
  el.id = `dl-btn-${nextId++}`;
  el.dataset.target = "#does-not-exist";
  el.dataset.filename = "build.txt";
  dom.document.body.appendChild(el);
  const hook = instantiateHook(hookDefinition, el);
  hook.mounted();

  const spy = spyOnDownload();
  assert.doesNotThrow(() => click(el));
  assert.equal(spy.created.length, 0, "без цели Blob не создаётся вовсе");
  spy.restore();
});
