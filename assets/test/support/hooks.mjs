// Loads the *actually compiled* colocated hooks — the same ES modules
// `app.js` imports in the browser (`import {hooks as colocatedHooks} from
// "phoenix-colocated/build_calculator"`), not a copy of the source.
//
// Why this is the only correct way to reach `.FeatInfo`/`.StatPop`: their
// `<script :type={Phoenix.LiveView.ColocatedHook}>` bodies live *inside*
// `builder_components.ex` (see the moduledoc on `stat_pop/1`), because
// `phx-hook=".Name"` resolves against the module whose *template* carries
// the attribute, not the module the matching `<script>` happens to sit in.
// Copying the JS out into a hand-written fixture would test a string that
// merely looks like the hook — LiveView compiles the real one straight out
// of the HEEx source at build time. This file imports THAT build output.
//
// LiveView writes one file per hook under a hashed, line-numbered name
// (`342_yjfay….js`) that shifts on any unrelated edit above the `<script>`
// in the same source file — so this reads through `index.js`, which is the
// one stable, generated map from fully-qualified hook name to that file
// (`hooks["BuildCalculatorWeb.BuilderComponents.StatPop"]`), exactly as
// `app.js` does.
import { fileURLToPath, pathToFileURL } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
// assets/test/support/hooks.mjs -> assets/test/support -> assets/test -> assets -> repo root
const repoRoot = path.resolve(here, "..", "..", "..");

// `mix precommit` runs in MIX_ENV=test (see `preferred_envs` in mix.exs), so
// the default matches what `mix compile` leaves behind for these tests to
// read. Overridable for a developer who wants to point this at a `dev`
// build instead.
const mixEnv = process.env.MIX_ENV || "test";

const indexPath = path.join(
  repoRoot,
  "_build",
  mixEnv,
  "phoenix-colocated",
  "build_calculator",
  "index.js"
);

let cachedHooks = null;

export async function loadHooks() {
  if (cachedHooks) return cachedHooks;
  let mod;
  try {
    mod = await import(pathToFileURL(indexPath).href);
  } catch (cause) {
    throw new Error(
      `Не найден собранный бандл колокированных хуков по пути:\n  ${indexPath}\n` +
        `Нужен "mix compile" (MIX_ENV=${mixEnv}) до JS-тестов — "mix precommit" ` +
        "уже делает шаги в этом порядке; напрямую запусти хотя бы раз " +
        `"MIX_ENV=${mixEnv} mix compile" из корня репозитория.`,
      { cause }
    );
  }
  cachedHooks = mod.hooks;
  return cachedHooks;
}

export async function loadHook(qualifiedName) {
  const hooks = await loadHooks();
  const hook = hooks[qualifiedName];
  if (!hook) {
    const known = Object.keys(hooks).sort().join("\n  ");
    throw new Error(
      `Хук "${qualifiedName}" не найден в скомпилированном бандле. Известные имена:\n  ${known}`
    );
  }
  return hook;
}
