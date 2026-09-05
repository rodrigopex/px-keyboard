/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXDimmable.h
 * @brief A PXToggleable that also has brightness.
 *
 * Separate from PXToggleable because only some indicators conform: a GPIO
 * pin is on or off, a PWM channel is not. PXLEDController holds a plain id
 * and asks -conformsToProtocol:@protocol(PXDimmable) at runtime to decide
 * whether the advertising state breathes or blinks -- a question the static
 * type cannot answer, which is the reason these are two protocols and not
 * one.
 */
#pragma once
#import "PXToggleable.h"

/**
 * @brief An indicator that can also be driven at partial brightness.
 */
@protocol PXDimmable <PXToggleable>

/**
 * @brief Drive the indicator at a fraction of full brightness.
 * @param level 0 = off, 255 = fully on.
 */
- (void)setLevel:(uint8_t)level;

@end
