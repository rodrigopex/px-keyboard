/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXLEDController.h
 * @brief Status indicator, driven from chan_ble_link.
 *
 * Deliberately knows nothing about Bluetooth: it takes an abstract status,
 * and the observer in the implementation does the BLE-state mapping.
 */
#pragma once
#import <Foundation/Foundation.h>

enum px_led_status {
	PX_LED_STATUS_OFF,
	PX_LED_STATUS_BLINK,
	PX_LED_STATUS_ON,
};

@interface PXLEDController: OZObject <SingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/**
 * @brief Set the indicator behaviour.
 *
 * PX_LED_STATUS_BLINK breathes on a dimmable indicator and blinks on one
 * that is only on/off.
 */
- (void)setLEDStatus:(enum px_led_status)status;

@end
