# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

# The objective-z module lives at the west workspace root, beside
# deps/zephyr. Where the workspace is, west answers: `west topdir` walks up
# for .west, so the module resolves wherever inside the workspace the
# checkout sits.
execute_process(
	COMMAND west topdir
	WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
	OUTPUT_VARIABLE ZEPHYR_EXTRA_MODULES
	OUTPUT_STRIP_TRAILING_WHITESPACE
	ERROR_QUIET
	RESULT_VARIABLE OBJZ_WEST_EXIT
)
string(APPEND ZEPHYR_EXTRA_MODULES "/objective-z")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(px_keyboard)

include_directories(include)

objz_transpile_sources(app
    src/GPIOPin.m
    src/GPIOOutput.m
    src/PWMOutput.m
    src/PXKeyboard.m
    src/PXHIDService.m
    src/PXBLEController.m
    src/PXLEDController.m
    src/main.m
)
