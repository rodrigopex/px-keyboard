/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXStaticBatterySource.m
 * @brief Fixed development implementation of PXBatterySource.
 */
#import "PXStaticBatterySource.h"

@implementation PXStaticBatterySource {
	uint8_t _percentage;
}

- (id)initWithChargePercentage:(uint8_t)percentage
{
	self = [super init];
	if (self) {
		if (percentage > 100U) {
			OZLog("PXStaticBatterySource: invalid percentage %u", percentage);
			return nil;
		}

		_percentage = percentage;
	}
	return self;
}

- (int)readChargePercentage:(uint8_t *)percentage
{
	*percentage = _percentage;
	return 0;
}

@end
