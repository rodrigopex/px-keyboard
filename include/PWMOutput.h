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
@interface PWMOutput : OZObject <PXDimmable>

/**
 * @brief Initialize from a devicetree PWM spec.
 * @param spec Pointer to the devicetree PWM spec (borrowed, not copied).
 * @return Initialized instance, or nil if the PWM device is not ready.
 */
- (id)initWithDTSpec:(const struct pwm_dt_spec *)spec;

/**
 * @brief The devicetree PWM spec this instance drives.
 *
 * Named `pwmSpec` rather than `spec`, and that is the point rather than a
 * concession. `GPIOPin` publishes `spec` returning a
 * `const struct gpio_dt_spec *`; one selector name gets one
 * `OZ_PROTOCOL_SEND_spec` with one return type, so two classes cannot
 * share it for different types. A distinct name is one of the two answers
 * oz_static's own diagnostic gives, and it costs nothing here -- no caller
 * wants these two interchangeably, since the whole reason `PXLEDController`
 * holds an `id<PXToggleable>` is that it does *not* care which one it has.
 */
- (const struct pwm_dt_spec *)pwmSpec;

@end
