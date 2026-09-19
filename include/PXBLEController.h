/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXBLEController.h
 * @brief BLE link state channel and controller entry point.
 *
 * Owns chan_ble_link, which is the single source of truth for the link
 * state -- there is no cached _state ivar, -state reads the channel.
 *
 * Implementation details such as Bluetooth callbacks, advertising gestures,
 * bond reset, and passkey display stay private to PXBLEController.m.
 */
#pragma once
#import <Foundation/Foundation.h>

#include <zephyr/zbus/zbus.h>

enum px_ble_state {
	PX_BLE_STATE_IDLE,
	PX_BLE_STATE_ADVERTISING,
	PX_BLE_STATE_CONNECTED,
};

struct msg_ble_link {
	enum px_ble_state state;
};

ZBUS_CHAN_DECLARE(chan_ble_link); /* Type: struct msg_ble_link */

@interface PXBLEController: OZObject <OZSingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/** @brief Enable Bluetooth; advertising starts once the stack is ready. */
- (void)start;

/** @brief Current link state, read from chan_ble_link. */
- (enum px_ble_state)state;

@end
