/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PWMOutput.h
 * @brief PWM-backed indicator — a dimmable PXToggleable.
 *
 * Wraps a Zephyr struct pwm_dt_spec the same way GPIOPin wraps a
 * struct gpio_dt_spec: the spec is borrowed, not copied, and the device is
 * checked for readiness at init.
 */
#pragma once
#import "PXDimmable.h"

#include <zephyr/drivers/pwm.h>
#include <zephyr/kernel.h>

/**
 * @brief A PWM channel driven as a variable-brightness indicator.
 */
/*
 * WORKAROUND (objective-z #290, see WORKAROUNDS.md): the devicetree spec is
 * kept private rather than exposed as a `spec` property, which is what
 * GPIOPin does. GPIOPin already publishes that selector returning a
 * `struct gpio_dt_spec *`, and oz_static builds one dispatch entry per
 * selector name, so two return types under one name collide.
 */
@interface PWMOutput : OZObject <PXDimmable>

/**
 * @brief Initialize from a devicetree PWM spec.
 * @param spec Pointer to the devicetree PWM spec (borrowed, not copied).
 * @return Initialized instance, or nil if the PWM device is not ready.
 */
- (id)initWithDTSpec:(const struct pwm_dt_spec *)spec;

@end
