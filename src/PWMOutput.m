/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PWMOutput.m
 * @brief PWM indicator implementation.
 */
#import "PWMOutput.h"

/*
 * The node's own period is the duty-cycle denominator, so a level maps onto
 * it directly. PWM_POLARITY_INVERTED lives in the devicetree node for the
 * board's active-low LEDs, which means "full pulse" already reads as "fully
 * lit" here -- this class never has to know the polarity.
 */
#define PX_LEVEL_MAX 255U

@implementation PWMOutput {
	const struct pwm_dt_spec *_spec;
	uint8_t _level;
}

- (id)initWithDTSpec:(const struct pwm_dt_spec *)spec
{
	self = [super init];
	if (self) {
		_spec = spec;
		_level = 0;

		if (!pwm_is_ready_dt(_spec)) {
			OZLog("PWMOutput: device not ready");
			return nil;
		}

		if (pwm_set_pulse_dt(_spec, 0) < 0) {
			OZLog("PWMOutput: initial pulse failed");
			return nil;
		}
	}
	return self;
}

- (void)setLevel:(uint8_t)level
{
	uint32_t pulse = (uint32_t)(((uint64_t)_spec->period * level) / PX_LEVEL_MAX);

	int ret = pwm_set_pulse_dt(_spec, pulse);
	if (ret < 0) {
		OZLog("PWMOutput: pulse failed: %d", ret);
		return;
	}

	_level = level;
}

- (BOOL)isActive
{
	return _level > 0;
}

- (void)setActive:(BOOL)active
{
	[self setLevel:active ? PX_LEVEL_MAX : 0];
}

- (void)toggle
{
	[self setActive:_level > 0 ? NO : YES];
}

- (int)cDescription:(char *)buf maxLength:(int)maxLen
{
	return snprintk(buf, maxLen, "<PWMOutput: %s ch %u, level=%u>", _spec->dev->name,
			_spec->channel, _level);
}

@end
