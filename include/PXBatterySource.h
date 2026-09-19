/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXBatterySource.h
 * @brief Hardware-independent source of a battery charge percentage.
 *
 * A source acquires battery state; it does not know how that state reaches a
 * host. PXBLEController owns the Zephyr Battery Service publication.
 */
#pragma once
#import <Foundation/Foundation.h>

#include <stdint.h>

/**
 * @brief Provide a Battery Service-compatible charge percentage.
 *
 * On success, -readChargePercentage: returns 0 and stores a value in the
 * inclusive range 0..100 at @p percentage. On failure it returns a nonzero
 * Zephyr-style error and leaves @p percentage unspecified. This keeps a
 * genuine 0% charge distinct from an unavailable measurement.
 */
@protocol PXBatterySource <OZObjectProtocol>

- (int)readChargePercentage:(uint8_t *)percentage;

@end
