/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXKeyboard.h
 * @brief Translate the four buttons into semantic input events.
 *
 * Owns the input-subsystem callback and publishes chan_input for each known
 * raw event. Consumers (PXHIDService, PXBLEController)
 * observe the channel; nothing calls into this class.
 */
#pragma once
#import <Foundation/Foundation.h>

#include <zephyr/kernel.h>
#include <zephyr/input/input.h>
#include <zephyr/zbus/zbus.h>

/**
 * @brief Key identity, and the bit position used by the HID service.
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
 * @brief Semantic input event kind.
 */
enum px_input_event_type {
	PX_INPUT_NONE,
	PX_INPUT_DOWN,
	PX_INPUT_UP,
	PX_INPUT_LONG_DOWN,
	PX_INPUT_LONG_UP,
};

struct msg_input {
	enum px_input_event_type type;
	enum px_key key;
};

ZBUS_CHAN_DECLARE(chan_input); /* Type: struct msg_input */

@interface PXKeyboard: OZObject <OZSingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/**
 * @brief Translate and publish one raw input event.
 *
 * Called from the input subsystem callback. Not meant for anything else.
 */
- (void)handleInputEvent:(struct input_event *)evt;

@end
