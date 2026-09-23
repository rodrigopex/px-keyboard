/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXLEDController.h
 * @brief Status indicator, driven from chan_ble_link and chan_input.
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
	PX_LED_STATUS_CONFIRM, /* on for a few seconds, then settles on OFF */
};

@interface PXLEDController: OZObject <OZSingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/**
 * @brief Set the indicator behaviour.
 *
 * PX_LED_STATUS_BLINK breathes on a dimmable indicator and blinks on one
 * that is only on/off.
 */
- (void)setLEDStatus:(enum px_led_status)status;
- (void)indicate;

/**
 * @brief Blink @p count on/off pairs, @p periodMs each half.
 *
 * On the status indicator, whose animation pauses for the burst and
 * resumes after it. The LED is held off for two seconds before the first
 * blink and after the last. Restarts rather than queues.
 */
- (void)blink:(unsigned int)count periodMs:(int)periodMs;

/**
 * @brief Record button @p index (an enum px_key) as held or released.
 *
 * While any button is held the LED is on, overriding the status; the
 * last release re-applies it. Ignored for display during a burst.
 */
- (void)setButton:(unsigned int)index held:(BOOL)held;

/** Burst timer tick. Not meant for anything else. */
- (void)burstStep;

@end
