/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXLEDController.h
 * @brief LED controller for power and BLE status indicators.
 */
#pragma once
#import <Foundation/Foundation.h>

#define PX_BLE_STATUS_OFF          0
#define PX_BLE_STATUS_ADVERTISING  1
#define PX_BLE_STATUS_CONNECTED    2

@interface PXLEDController : OZObject

- (id)init;

/**
 * @brief Set BLE status LED behavior.
 * @param status PX_BLE_STATUS_OFF, PX_BLE_STATUS_ADVERTISING (blink), or PX_BLE_STATUS_CONNECTED (solid).
 */
- (void)setBLEStatus:(int)status;

@end
