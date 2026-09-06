/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXToggleable.h
 * @brief What every status indicator can do.
 *
 * PXLEDController talks to an indicator through this protocol rather than
 * to a concrete class, because this board offers two of them: LED0 on a
 * plain GPIO pin, and pwm_led0 through &pwm0.
 */
#pragma once
#import <Foundation/Foundation.h>

/**
 * @brief An indicator that can be switched on, off, or inverted.
 *
 * `<ObjectProtocol>` is what lets PXLEDController ask its indicator a
 * runtime question at all. Clang resolves a message sent to an
 * `id<PXToggleable>` against this protocol and its super-protocols and
 * nowhere else, so `[_indicator conformsToProtocol:@protocol(PXDimmable)]`
 * was `error: no known instance method for selector 'conformsToProtocol:'`
 * however plainly OZObject declares it -- objective-z #307, fixed there and
 * adopted here. It asks nothing of GPIOOutput or PWMOutput: every method it
 * declares is defined once, on OZObject, and an inherited implementation
 * satisfies a protocol requirement.
 */
@protocol PXToggleable <ObjectProtocol>

/** @brief Logical state of the indicator. */
- (BOOL)isActive;

/** @brief Drive the indicator fully on or fully off. */
- (void)setActive:(BOOL)active;

/** @brief Invert the current state. */
- (void)toggle;

@end
