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

#include <zephyr/app_version.h>
#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>

/*
 * Mirrors samples/zbus_service's lis_print_temp: an observer purely to
 * watch.
 *
 * Async, like every other observer in this app, and for one rule rather
 * than a per-case judgement: **a listener never runs on the publisher's
 * stack.** A synchronous one does, and the publishers here are all
 * interrupt-driven paths with small stacks -- chan_keys is published from
 * the input subsystem's own thread (CONFIG_INPUT_MODE_THREAD, 1024 bytes
 * by default), and chan_ble_link from the Bluetooth connection callbacks
 * (1200).
 *
 * The LED listener was synchronous and overflowed the Bluetooth thread.
 * This one was then left synchronous on the argument that it is only a
 * printk and its publisher had room -- an argument built on the wrong
 * number: the input path is 1024, not the 2048 system work queue. Applying
 * the rule costs a work-queue hop on a debug log and removes the whole
 * class of fault instead of re-deciding it per listener.
 */
ZBUS_ASYNC_LISTENER_DEFINE(alis_keys_debug,
			   OZFN(^(const struct zbus_channel *chan, const void *message) {
			     const struct msg_keys *keys = message;

			     OZLog("keys: mask=0x%02x long=0x%02x", keys->mask, keys->long_mask);
			   }));

ZBUS_CHAN_ADD_OBS(chan_keys, alis_keys_debug, 4);

/*
 * Every singleton overrides -getDescription:maxLength:, so dumping the whole
 * app is four %@ conversions. SHELL_CMD_REGISTER wants a raw handler
 * pointer, so the block needs OZFN.
 */
SHELL_CMD_REGISTER(px_info, NULL, "Dump PX keyboard state",
		   OZFN(^(const struct shell *sh, size_t argc, char **argv) {
		     ARG_UNUSED(sh);
		     ARG_UNUSED(argc);
		     ARG_UNUSED(argv);

		     OZLog("%@", [PXKeyboard sharedInstance]);
		     OZLog("%@", [PXBLEController sharedInstance]);
		     OZLog("%@", [PXHIDService sharedInstance]);
		     OZLog("%@", [PXLEDController sharedInstance]);

		     return 0;
		   }));

int main(void)
{
	/* The version on the banner, so a console log identifies the build
	 * that produced it. Nine flashes into this app there was no way to
	 * tell which one was on the board. From the VERSION file via
	 * Zephyr's app-version machinery, so `west build` is the only
	 * place it is written down. */
	OZLog("=== PX Keyboard v%s ===", APP_VERSION_STRING);

	[[PXBLEController sharedInstance] start];

	return 0;
}
