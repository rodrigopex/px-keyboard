/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

#import <Foundation/Foundation.h>
#import "PXBLEController.h"
#import "PXKeyboard.h"
#include <zephyr/kernel.h>

int main(void)
{
    OZLog("=== PX Keyboard ===");

    PXBLEController *ble = [PXBLEController shared];
    PXKeyboard *kb = [[PXKeyboard alloc] initWithBLEController:ble];

    [ble start];
    [kb run]; /* never returns */

    return 0;
}
