/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file main.m
 * @brief App entry point and app-level wiring.
 *
 * Thin on purpose. Every subsystem is a singleton built by +initialize
 * before main runs, and every connection between them is a file-scope
 * ZBUS_CHAN_ADD_OBS in the observing subsystem's own translation unit. All
 * that is left here is enabling Bluetooth, one debug observer, and a shell
 * command.
 */
#import <Foundation/Foundation.h>
#import "PXBLEController.h"
#import "PXHIDService.h"
#import "PXKeyboard.h"
#import "PXLEDController.h"

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>

/*
 * Mirrors samples/zbus_service's lis_print_temp: an observer purely to
 * watch.
 *
 * Left synchronous, unlike the three real ones, and the reason is worth
 * stating since the LED listener had to stop being: a synchronous listener
 * runs on the publisher's stack, so it is only safe when it is shallow and
 * the publisher is not. This one is a single printk, and chan_keys is
 * published from the input-subsystem callback -- the system work queue,
 * 2048 bytes. The LED one ran from a Bluetooth connection callback at 1200
 * and overflowed it.
 */
OZM(ZBUS_LISTENER_DEFINE, lis_keys_debug, ^(const struct zbus_channel *chan) {
	const struct msg_keys *keys = zbus_chan_const_msg(chan);

	OZLog("keys: mask=0x%02x long=0x%02x", keys->mask, keys->long_mask);
});

ZBUS_OBS_DECLARE(lis_keys_debug)

ZBUS_CHAN_ADD_OBS(chan_keys, lis_keys_debug, 4);

/*
 * Every singleton overrides -cDescription:maxLength:, so dumping the whole
 * app is four %@ conversions. SHELL_CMD_REGISTER takes a raw handler
 * pointer, hence OZM.
 */
OZM(SHELL_CMD_REGISTER, px_info, NULL, "Dump PX keyboard state",
    ^(const struct shell *sh, size_t argc, char **argv) {
	ARG_UNUSED(sh);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	OZLog("%@", [PXKeyboard sharedInstance]);
	OZLog("%@", [PXBLEController sharedInstance]);
	OZLog("%@", [PXHIDService sharedInstance]);
	OZLog("%@", [PXLEDController sharedInstance]);

	return 0;
});

int main(void)
{
	OZLog("=== PX Keyboard ===");

	[[PXBLEController sharedInstance] start];

	return 0;
}
