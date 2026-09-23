alias b := build
alias c := clean
alias f := flash
alias m := monitor
alias rb := rebuild

# The board is overridable per invocation, and the nrf54l05 has recipes of
# its own below: `just board=nrf54l15dk/nrf54l05/cpuapp rebuild` is what
# `just rebuild-54` runs.
board := "nrf52833dk/nrf52833"
board_54 := "nrf54l15dk/nrf54l05/cpuapp"
build_dir := "build"

# A snippet is a west argument, not a cmake one, so it cannot go through the
# positional flags (those land after `--`). Empty means no snippet:
# `just snippet=zview rebuild` adds the thread and stack introspection that
# `kernel thread stacks` reads.
snippet := ""
snippet_arg := if snippet == "" { "" } else { "-S " + snippet }

# px-keyboard is not a west project, so nothing puts it in the manifest and
# nothing sets its environment up. It sits *inside* the workspace, though, so
# west still finds ../.west by walking up from here -- which is why these
# recipes can run from px-keyboard rather than from the workspace root.
#
# ZEPHYR_BASE is what CMakeLists.txt hints find_package(Zephyr) with, and it
# has to be absolute: the build runs with -d, so cmake's working directory is
# not this one.
workspace := parent_directory(justfile_directory())
export ZEPHYR_BASE := workspace / "deps/zephyr"

# Two SDKs are installed side by side (1.0.0 and 1.0.1); pinning one keeps a
# build from silently changing toolchain when a third arrives.
# Override per invocation: `just sdk=~/.local/zephyr-sdk-1.0.0 rebuild`.
export ZEPHYR_SDK_INSTALL_DIR := sdk

sdk := home_directory() / ".local/zephyr-sdk-1.0.1"

# The 52833 DK's CDC-ACM port. Override when a different board or USB port is
# in use -- the nrf54l05 DK enumerates its own:
# `just tty=/dev/tty.usbmodem0006850372582 monitor`.
tty := "/dev/tty.usbmodem0006850372581"

# `just` alone lists what there is rather than building something.
default:
    @just --list

# Extra cmake flags are positional and variadic, so a Kconfig fragment can be
# tried without editing anything here: `just build -DCONFIG_SHELL=y
# -DCONFIG_LOG=n`. `run` forwards them to its build too.

# Use `rebuild` after touching prj.conf, the overlay, CMakeLists or the
# transpiler -- cmake re-runs on those, but a stale build/ has burned enough
# time here to be worth the explicit recipe.

# Incremental build.
build *flags:
    west build -b {{ board }} {{ snippet_arg }} -d {{ build_dir }} . -- {{ flags }}

# Pristine build.
rebuild *flags: clean
    west build -b {{ board }} {{ snippet_arg }} -d {{ build_dir }} . -- {{ flags }}

# `rm -rf`, not `rip`: rip moves the bytes to /tmp/graveyard-$USER, which frees
# no space, and a Zephyr build directory is most of a gigabyte.

# Delete the build directory.
clean:
    rm -rf {{ build_dir }}

# Flash the DK over its on-board debugger.
flash:
    west flash -d {{ build_dir }}

# Attach to the DK's serial console.
monitor:
    tio {{ tty }}

# Build, flash and monitor -- the loop hardware work runs in.
run *flags: (build flags) flash monitor

# The nrf54l05 variants of the three board-bound recipes. flash and monitor
# need none: the build directory records the runner, and tty is overridden
# on its own.

# Incremental build for the nrf54l05 DK.
build-54 *flags:
    just board={{ board_54 }} snippet={{ quote(snippet) }} sdk={{ quote(sdk) }} build_dir={{ quote(build_dir) }} build {{ flags }}

# Pristine build for the nrf54l05 DK.
rebuild-54 *flags:
    just board={{ board_54 }} snippet={{ quote(snippet) }} sdk={{ quote(sdk) }} build_dir={{ quote(build_dir) }} rebuild {{ flags }}

# Build, flash and monitor on the nrf54l05 DK.
run-54 *flags: (build-54 flags) flash monitor
