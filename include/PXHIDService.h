/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXHIDService.h
 * @brief BLE HID keyboard GATT service — singleton wrapping report map,
 *        notification logic, and key-to-HID mapping.
 */
#pragma once
#import <Foundation/Foundation.h>

@interface PXHIDService : OZObject

/** Singleton accessor (created via +initialize before main). */
+ (PXHIDService *)shared;

/**
 * @brief Build and send a HID keyboard report from a button bitmask.
 * @param mask Bitmask of pressed buttons (bit0=sw0, bit1=sw1, ...).
 */
- (void)sendReportForMask:(uint8_t)mask;

/** YES if the host has subscribed to HID input notifications. */
- (BOOL)isSubscribed;

@end
