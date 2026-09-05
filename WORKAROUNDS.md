# Workarounds

Five places in this app are shaped around `oz_static` defects rather than around what
the code wants to say. Each is filed upstream with a minimal reproducer. **When the
issue closes, revert the workaround** — this file exists so that is a mechanical job
rather than an archaeology one.

Upstream tracker: [rodrigopex/objective-z](https://github.com/rodrigopex/objective-z),
[Project #4](https://github.com/users/rodrigopex/projects/4). All five failed the same
way — an unreadable GCC error on generated C, never a located error on the `.m`.

Verify a fix with the gate that found these:

```sh
cd ..
ZEPHYR_BASE=$PWD/deps/zephyr west build -b nrf52833dk/nrf52833 -p always \
    -d px-keyboard/build px-keyboard
```

---

## 1. The gesture table is at file scope — [#287](https://github.com/rodrigopex/objective-z/issues/287)

*An array ivar loses its dimension in the generated struct.*

`src/PXBLEController.m:170` holds `static SEL sGestures[PX_KEY_COUNT];` outside the
class. It belongs inside, since it is per-instance state in every sense but this one.

**Revert:** move it into the `@implementation` ivar block at line 172 as
`SEL _gestures[PX_KEY_COUNT];`, then rename the five uses (lines ~194-197, 200, 302)
from `sGestures[...]` back to `_gestures[...]`. Drop the explanatory comment above the
declaration.

## 2. The indicator ivar is a bare `id` — [#288](https://github.com/rodrigopex/objective-z/issues/288)

*An `OZM` between an `@interface` and its `@implementation` leaves the whole
`@implementation` untranslated.*

`src/PXLEDController.m:120` declares `id _indicator;` where the design wants
`id<PXToggleable> _indicator;`, and three sends carry a cast to compensate.

**Revert:** make the ivar `id<PXToggleable> _indicator;` and drop the
`(id<PXToggleable>)` casts at lines ~174, 179 and 196. Leave the `(id<PXDimmable>)`
cast in the timer block alone — that one is a deliberate narrowing, not a workaround.

**Note:** the comment above that ivar blames a protocol-qualified `id` ivar. That
diagnosis was wrong — the ivar type is irrelevant, the trigger is positional. Correct
the comment or delete it with the workaround.

## 3. The LED singleton pointer sits above the `OZM` blocks — [#288](https://github.com/rodrigopex/objective-z/issues/288)

Same defect, second symptom: the declaration reached GCC as `PXLEDController *`
rather than `struct PXLEDController *`. Compare
[OZ-004](https://github.com/rodrigopex/objective-z/issues/37).

`src/PXLEDController.m:36` declares `static PXLEDController *sSharedLEDController;`
near the top of the file. The other three singletons put theirs immediately before
their `@implementation` (`PXBLEController.m:158`, `PXHIDService.m:199`,
`PXKeyboard.m:35`).

**Revert:** move it down to just above `@implementation PXLEDController`, matching the
other three, and drop the comment explaining the placement.

## 4. The shell handler is a named C function — [#289](https://github.com/rodrigopex/objective-z/issues/289)

*A second `OZM` in the same file keeps its block literal at the call site.*

`src/main.m` already carries one `OZM(ZBUS_LISTENER_DEFINE, …)`, so the shell command
could not be a second one. It is a `static int px_info_handler(...)` at line 45 with a
bare `SHELL_CMD_REGISTER` at line 59.

**Revert:** collapse both into one invocation, which is what the rest of the file's
wiring looks like:

```objc
OZM(SHELL_CMD_REGISTER, px_info, NULL, "Dump PX keyboard state",
    ^(const struct shell *sh, size_t argc, char **argv) {
	ARG_UNUSED(sh);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	OZLog("%@", [PXKeyboard sharedInstance]);
	OZLog("%@", [PXBLEController sharedInstance]);
	OZLog("%@", [PXHIDService sharedInstance]);
	OZLog("%@", [PXLEDController sharedInstance]);

	return 0;
});
```

## 5. `PWMOutput` has no `spec` property — [#290](https://github.com/rodrigopex/objective-z/issues/290)

*Two classes publishing one selector with different return types miscompile the
dispatch shim.*

`GPIOPin` publishes `spec` returning `const struct gpio_dt_spec *`. `PWMOutput`
wanting `spec` for `const struct pwm_dt_spec *` broke `OZ_PROTOCOL_SEND_spec`, so
`include/PWMOutput.h` keeps the spec as a private ivar with no accessor — asymmetric
with `GPIOPin`, which it otherwise mirrors.

**Revert:** add back the property and its synthesis, and drop the comment above the
`@interface`:

```objc
/* include/PWMOutput.h */
@property(nonatomic, readonly, unsafe_unretained) const struct pwm_dt_spec *spec;

/* src/PWMOutput.m, inside @implementation */
@synthesize spec = _spec;
```
