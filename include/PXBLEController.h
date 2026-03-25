/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXBLEController.h
 * @brief BLE state machine with LED status indicators.
 */
#pragma once
#import <Foundation/Foundation.h>
#import "PXLEDController.h"

#define PX_BLE_STATE_IDLE         0
#define PX_BLE_STATE_ADVERTISING  1
#define PX_BLE_STATE_CONNECTED    2

@interface PXBLEController : OZObject

/** Singleton accessor (created via +initialize before main). */
+ (PXBLEController *)shared;

/** Enable Bluetooth and start advertising when ready. */
- (void)start;

/** Current BLE state (PX_BLE_STATE_*). */
- (int)state;

/** Called by BLE low-level layer when BT stack is ready. */
- (void)onBTReady;

/** Called by BLE low-level layer on connection. */
- (void)onConnected;

/** Called by BLE low-level layer on disconnection. */
- (void)onDisconnected;

/** Unpair all bonded devices and restart advertising. */
- (void)forgetBondAndReadvertise;

@end
