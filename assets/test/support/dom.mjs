// A happy-dom `Window` installed onto Node's `globalThis`.
//
// Why global rather than dependency-injected: the compiled hooks are
// ordinary browser code (`document.createElement`, `matchMedia`,
// `window.addEventListener`, …) — they read `document`/`window`/`matchMedia`
// as free identifiers resolved at CALL time, exactly as they will in a real
// page. Passing a `document` parameter around would mean testing a version
// of the hook that does not exist; this file makes the *real* compiled
// source work unmodified by giving it the globals it expects, the same way
// a browser tab does.
import { Window } from "happy-dom";

export function installDom({ width = 1440, height = 900 } = {}) {
  const window = new Window({ url: "http://localhost/", width, height });
  const document = window.document;

  globalThis.window = window;
  globalThis.document = document;
  // `.bind(window)` matters: happy-dom's `matchMedia` reads `this.innerWidth`
  // internally, and an unbound reference loses that receiver.
  globalThis.matchMedia = window.matchMedia.bind(window);

  return { window, document };
}

export function uninstallDom() {
  for (const key of ["window", "document", "matchMedia"]) {
    delete globalThis[key];
  }
}
