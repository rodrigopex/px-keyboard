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

/* Mirrors samples/zbus_service's lis_print_temp: an observer purely to watch. */
OZM(ZBUS_LISTENER_DEFINE, lis_keys_debug, ^(const struct zbus_channel *chan) {
	const struct msg_keys *keys = zbus_chan_const_msg(chan);

	OZLog("keys: mask=0x%02x long=0x%02x", keys->mask, keys->long_mask);
});

ZBUS_OBS_DECLARE(lis_keys_debug)

ZBUS_CHAN_ADD_OBS(chan_keys, lis_keys_debug, 4);

/*
 * Every singleton overrides -cDescription:maxLength:, so dumping the whole
 * app is four %@ conversions.
 *
 * WORKAROUND (objective-z #289, see WORKAROUNDS.md): a named C function
 * rather than a second inline block through OZM. This file already carries
 * one OZM, and a second one keeps its block literal at the call site, so
 * the `^` reaches the C compiler. A plain static handler is what
 * samples/zbus_service does for its own callback anyway.
 */
static int px_info_handler(const struct shell *sh, size_t argc, char **argv)
{
	ARG_UNUSED(sh);
	ARG_UNUSED(argc);
	ARG_UNUSED(argv);

	OZLog("%@", [PXKeyboard sharedInstance]);
	OZLog("%@", [PXBLEController sharedInstance]);
	OZLog("%@", [PXHIDService sharedInstance]);
	OZLog("%@", [PXLEDController sharedInstance]);

	return 0;
}

SHELL_CMD_REGISTER(px_info, NULL, "Dump PX keyboard state", px_info_handler);

int main(void)
{
	OZLog("=== PX Keyboard ===");

	[[PXBLEController sharedInstance] start];

	return 0;
}
