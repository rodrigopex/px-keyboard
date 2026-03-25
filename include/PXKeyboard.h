/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXKeyboard.h
 * @brief HID keyboard: maps buttons to keycodes, sends reports, detects long-press.
 */
#pragma once
#import <Foundation/Foundation.h>
#import "PXBLEController.h"

@interface PXKeyboard : OZObject

- (id)initWithBLEController:(PXBLEController *)ble;

/** Main loop — polls buttons at 50Hz, never returns. */
- (void)run;

@end
