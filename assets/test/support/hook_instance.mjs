// Mirrors what LiveView's own `ViewHook` constructor does with an
// object-literal hook (`deps/phoenix_live_view/assets/js/phoenix_live_view/view_hook.ts`,
// `ViewHook` constructor): it copies every enumerable key of the callbacks
// object onto a *fresh* instance, plus `el` — it does NOT use prototypal
// delegation. That copy is why a method like `mounted()` can call
// `this.applyMode()` and reach a sibling method defined on the same object
// literal: both ended up as own properties of the same instance.
//
// A naive `hook.mounted.call({ el })` would NOT reproduce this: `applyMode`
// would be missing from the plain `{ el }` context, and the call would throw.
export function instantiateHook(hookDefinition, el) {
  return Object.assign({}, hookDefinition, { el });
}
