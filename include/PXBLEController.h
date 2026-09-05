/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXBLEController.h
 * @brief BLE link state machine, and the long-press gestures that drive it.
 *
 * Owns chan_ble_link, which is the single source of truth for the link
 * state -- there is no cached _state ivar, -state reads the channel.
 */
#pragma once
#import <Foundation/Foundation.h>

#include <zephyr/kernel.h>
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

@interface PXBLEController : OZObject <SingletonProtocol>

+ (void)initialize;
+ (instancetype)sharedInstance;

/** @brief Enable Bluetooth; advertising starts once the stack is ready. */
- (void)start;

/** @brief Current link state, read from chan_ble_link. */
- (enum px_ble_state)state;

/* ---- Called by the BLE low-level callbacks ---- */

/** @brief The BT stack finished initializing. */
- (void)onBTReady;

/** @brief A central connected. */
- (void)onConnected;

/** @brief The central went away. */
- (void)onDisconnected;

/* ---- Gestures ---- */

/**
 * @brief Dispatch the long-press gesture table on each rising edge.
 * @param longMask Bitmask of keys held past the long-press delay.
 */
- (void)handleLongMask:(uint8_t)longMask;

/** @brief sw0 — stop advertising if advertising, start it if not. */
- (void)toggleAdvertising;

/** @brief sw1 — drop the current link, keeping the bond. */
- (void)disconnectLink;

/** @brief sw2 — push a battery level to the host. */
- (void)reportBatteryLevel;

/** @brief sw3 — forget every bond and go back to advertising. */
- (void)forgetBond;

@end
