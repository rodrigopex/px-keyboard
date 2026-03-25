# SPDX-License-Identifier: Apache-2.0

cmake_minimum_required(VERSION 3.20.0)

set(ZEPHYR_EXTRA_MODULES "${CMAKE_CURRENT_SOURCE_DIR}/../objective-z")

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(px_keyboard)

include_directories(include)

objz_transpile_sources(app
    src/GPIOPin.m
    src/GPIOOutput.m
    src/PXLEDController.m
    src/PXBLEController.m
    src/PXHIDService.m
    src/PXKeyboard.m
    src/main.m
)
