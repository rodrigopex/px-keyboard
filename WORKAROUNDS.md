# Workarounds

One left, and it is permanent. The other four are gone: the `oz_static` defects
behind them are fixed and merged, so this file no longer tracks a backlog.

Upstream tracker: [rodrigopex/objective-z](https://github.com/rodrigopex/objective-z),
[Project #4](https://github.com/users/rodrigopex/projects/4).

---

## `PWMOutput` has no `spec` property — [#290](https://github.com/rodrigopex/objective-z/issues/290)

**Permanent, and now enforced rather than merely advisable.**

`GPIOPin` publishes `spec` returning `const struct gpio_dt_spec *`. `PWMOutput` wants
the same selector for `const struct pwm_dt_spec *`, so `include/PWMOutput.h` keeps its
spec as a private ivar with no accessor — asymmetric with `GPIOPin`, which it otherwise
mirrors.

This started as a workaround for a miscompilation: `OZ_PROTOCOL_SEND_spec` was emitted
with one implementor's return type and routed to both, which GCC rejected while naming
generated code nobody wrote. #290 made that a located error, so the shape is now
*diagnosed* rather than silently broken — but it is still not allowed. Adding the
property back gives:

```
oz_static: error: 'spec' is dispatched dynamically, so one shared
'OZ_PROTOCOL_SEND_spec' routes every implementor -- but GPIOPin returns
'const struct gpio_dt_spec*' and PWMOutput returns 'const struct pwm_dt_spec*'.
Dispatch is keyed on the selector name alone, so the two cannot share one.
Rename one of them, or give them the same return type.
```

Verified by trying it, not assumed.

**If you want the accessor**, take one of the two ways the diagnostic names: give it a
distinct selector (`-pwmSpec`), or have both return an opaque `const void *`. Reverting
to a shared `spec` is not an option and will not become one — dispatch is keyed on the
selector name, so it cannot be.

---

## Removed, with the fix that removed them

| Was | Fixed by | Reverted |
| --- | --- | --- |
| gesture table at file scope instead of an ivar | [#287](https://github.com/rodrigopex/objective-z/issues/287) | `PXBLEController.m` — `SEL _gestures[PX_KEY_COUNT]` is an ivar again |
| `id _indicator` instead of `id<PXToggleable>` | [#288](https://github.com/rodrigopex/objective-z/issues/288) | `PXLEDController.m` — protocol-typed, casts dropped |
| singleton pointer hoisted above the `OZM` blocks | [#288](https://github.com/rodrigopex/objective-z/issues/288) | `PXLEDController.m` — back beside its `@implementation`, like the other three |
| shell handler as a named C function | [#289](https://github.com/rodrigopex/objective-z/issues/289) | `main.m` — one `OZM(SHELL_CMD_REGISTER, …, ^{…})` again |

## Not a workaround, but a required follow-on

`-cDescription:maxLength:` takes a `size_t` capacity as of
[#294](https://github.com/rodrigopex/objective-z/issues/294) — `snprintf`'s shape. All
seven overrides here were updated. The build tolerated the old `int` through an
implicit conversion, so this was correctness rather than a fix.
