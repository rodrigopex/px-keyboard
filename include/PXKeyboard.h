/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXKeyboard.h
 * @brief The four buttons, as one zbus channel.
 *
 * Owns the input-subsystem callback and publishes chan_keys whenever a key
 * or long-press bit changes. Consumers (PXHIDService, PXBLEController)
 * observe the channel; nothing calls into this class.
 */
#pragma once
#import <Foundation/Foundation.h>

#include <zephyr/kernel.h>
#include <zephyr/input/input.h>
#include <zephyr/zbus/zbus.h>

/**
 * @brief Key identity, and the bit position it occupies in struct msg_keys.
 *
 * The order is the devicetree button order (sw0..sw3), which is also the
 * order the HID keymap is indexed by, so consumers need no switch.
 */
enum px_key {
	PX_KEY_P, /* sw0 */
	PX_KEY_X, /* sw1 */
	PX_KEY_K, /* sw2 */
	PX_KEY_B, /* sw3 */
	PX_KEY_COUNT,
};

/**
 * @brief Full button state, published on every change.
 */
struct msg_keys {
	uint8_t mask;      /* BIT(PX_KEY_*) — currently held */
	uint8_t long_mask; /* BIT(PX_KEY_*) — held past long-delay-ms */
};

ZBUS_CHAN_DECLARE(chan_keys); /* Type: struct msg_keys */

@interface PXKeyboard: OZObject <OZSingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/**
 * @brief Fold one input event into the key state and publish if it changed.
 *
 * Called from the input subsystem callback. Not meant for anything else.
 */
- (void)handleInputEvent:(struct input_event *)evt;

/** @brief Bitmask of currently held keys. */
- (uint8_t)mask;

/** @brief Bitmask of keys held past the long-press delay. */
- (uint8_t)longMask;

@end
