/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXHIDService.h
 * @brief BLE HID keyboard GATT service.
 *
 * Observes chan_input, owns held-key state, and sends HID input reports.
 * Upstream Zephyr has no HID-over-GATT service (see
 * deps/zephyr/subsys/bluetooth/services/), so the report map, the GATT
 * table and the notification live here.
 */
#pragma once
#import <Foundation/Foundation.h>

#include <zephyr/kernel.h>

struct msg_input;

@interface PXHIDService: OZObject <OZSingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/** @brief Update held-key state from one semantic input event. */
- (void)handleInput:(const struct msg_input *)input;

/**
 * @brief Build and send a HID keyboard report from a key bitmask.
 * @param mask Bitmask of held keys (BIT(PX_KEY_*)).
 */
- (void)sendReportForMask:(uint8_t)mask;

/** @brief YES once the host has subscribed to HID input notifications. */
- (BOOL)isSubscribed;

@end
