/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXStaticBatterySource.h
 * @brief Fixed battery source for boards without a physical measurement.
 */
#pragma once
#import "PXBatterySource.h"

/**
 * @brief Return one configured Battery Service-compatible percentage.
 *
 * This is a development source, not a battery measurement. Initialisation
 * fails when @p percentage is outside 0..100, so a successful instance
 * always upholds the PXBatterySource contract.
 */
@interface PXStaticBatterySource: OZObject <PXBatterySource>

- (id)initWithChargePercentage:(uint8_t)percentage;

@end
