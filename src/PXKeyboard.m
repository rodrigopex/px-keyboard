/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXKeyboard.m
 * @brief Maps buttons to HID keycodes, sends BLE HID reports, handles long-press combo.
 *        Includes input subsystem callback for button state tracking.
 */
#import "PXKeyboard.h"
#import "PXHIDService.h"
#include <zephyr/kernel.h>
#include <zephyr/input/input.h>
#include <zephyr/dt-bindings/input/input-event-codes.h>

/* Long-press: sw0 + sw1 held for 5 seconds */
#define COMBO_MASK         0x03
#define COMBO_HOLD_MS      5000

/* ---- Input subsystem button tracking ---- */

static volatile uint8_t sPressedMask;

static void buttons_input_cb(struct input_event *evt, void *user_data)
{
        ARG_UNUSED(user_data);

        if (evt->type != INPUT_EV_KEY) {
                return;
        }

        uint8_t bit;

        switch (evt->code) {
        case INPUT_KEY_0:
                bit = BIT(0);
                break;
        case INPUT_KEY_1:
                bit = BIT(1);
                break;
        case INPUT_KEY_2:
                bit = BIT(2);
                break;
        case INPUT_KEY_3:
                bit = BIT(3);
                break;
        default:
                return;
        }

        if (evt->value) {
                sPressedMask |= bit;
        } else {
                sPressedMask &= ~bit;
        }
}

INPUT_CALLBACK_DEFINE(NULL, buttons_input_cb, NULL);

/* ---- PXKeyboard ---- */

@implementation PXKeyboard {
    PXBLEController *_ble;
}

- (id)initWithBLEController:(PXBLEController *)ble
{
    self = [super init];
    if (self) {
        _ble = ble;
    }
    return self;
}

- (void)run
{
    uint8_t prevMask = 0;
    int64_t comboStartTime = 0;
    BOOL comboActive = NO;

    OZLog("PXKeyboard: running (50Hz scan)");

    for (;;) {
        uint8_t mask = sPressedMask;

        /* Send HID report on state change */
        if (mask != prevMask) {
            [[PXHIDService shared] sendReportForMask:mask];
            prevMask = mask;
        }

        /* Long-press combo detection: sw0 + sw1 for 5s */
        if ((mask & COMBO_MASK) == COMBO_MASK) {
            if (!comboActive) {
                comboActive = YES;
                comboStartTime = k_uptime_get();
            } else {
                int64_t elapsed = k_uptime_get() - comboStartTime;
                if (elapsed >= COMBO_HOLD_MS) {
                    OZLog("PXKeyboard: long-press combo detected!");
                    [_ble forgetBondAndReadvertise];
                    comboActive = NO;
                    /* Wait for buttons to be released */
                    while ((sPressedMask & COMBO_MASK) == COMBO_MASK) {
                        k_msleep(50);
                    }
                }
            }
        } else {
            comboActive = NO;
        }

        k_msleep(20);
    }
}

@end
