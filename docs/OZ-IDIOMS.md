# Objective-Z idioms in px-keyboard

The conventions this app runs on, each with the reason and the file you can
check it in. Language-level rules (ARC, the subset, blocks) belong to the
[objective-z repo](https://github.com/rodrigopex/objective-z); this file
records only what _this app_ does with them.

## 1. One subsystem, one file, one singleton

Every subsystem is one `.m` file whose class owns a `+sharedInstance`, built
in `+initialize` before `main` runs. Nothing calls an initialiser by hand,
and `main` only starts the one outer-world side effect (BLE). See
`PXKeyboard.m`, `PXBLEController.m`, `PXHIDService.m`, `PXLEDController.m`.

## 2. A subsystem owns its channel; observers subscribe from their own file

`ZBUS_CHAN_DEFINE` lives in the publishing subsystem's translation unit, and
the message type lives in its header. Each consumer registers itself with
`ZBUS_CHAN_ADD_OBS` next to the listener it defines, in its own file. There
is no central wiring table: grep `ZBUS_CHAN_ADD_OBS` and you have the whole
graph.

## 3. Observers are async by default

A plain listener runs on the publisher's stack; the publishers here are
small interrupt-driven paths (input thread 1024 bytes, BT RX 1200). One
synchronous LED listener already overflowed the BT thread. New observers are
`ZBUS_ASYNC_LISTENER_DEFINE` unless someone can argue why they must run
inline. The argument is written once in `main.m`, not re-litigated per
listener.

## 4. Hoisted blocks capture nothing

A block carried into a Zephyr macro by `OZFN`/`OZM` is hoisted to file
scope, so it reaches objects through `+sharedInstance` (or file-scope
statics), never through a capture. Prefer `OZFN`: it leaves the enclosing
macro visible to Clang. Use `OZM` only where the macro token-pastes its
argument — the `INPUT_CALLBACK_DEFINE` case in `PXKeyboard.m`, which also
explains what goes wrong otherwise. And two files must not carry a hoisted
block on the same line: the generated symbol is named after the block's
own-file line and column, so identical positions in two files collide at
link (see the comment above `alis_keys_debug` in `main.m`).

## 5. Every singleton implements `-getDescription:maxLength:`

That single message is what makes `px_info` a four-line dump of the whole
app. Add a subsystem, add the method — otherwise the dump silently goes
stale.

## 6. Zephyr facts live next to what forces them

Stack sizes, errnos and Kconfig choices in `prj.conf` carry the measurement
and the failure that motivated them. Change the number, and the comment next
to it is the thing to update.
