/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXKeyboard.m
 * @brief Input subsystem -> chan_input.
 *
 * The buttons arrive as two families of event codes. The raw ones
 * (INPUT_KEY_0..3) come straight from the gpio-keys node in the board
 * devicetree. The long-press ones (INPUT_KEY_M/N/Y/Z) come from the
 * zephyr,input-longpress node in app.overlay, which republishes a held key
 * under a second code after long-delay-ms and clears it on release. Both
 * families reach this one callback and become semantic events.
 */
#import "PXKeyboard.h"

#include <zephyr/dt-bindings/input/input-event-codes.h>

ZBUS_CHAN_DEFINE(chan_input, struct msg_input, NULL, NULL, ZBUS_OBSERVERS_EMPTY,
		 ZBUS_MSG_INIT(.type = PX_INPUT_NONE, .key = PX_KEY_P));

/*
 * The callback is a block so the wiring reads as one unit, which means it
 * must reach its object the way every hoisted block does -- through the
 * singleton, never through a capture. OZM carries the block into the macro;
 * see include/oz_sdk/Foundation/OZMacro.h.
 *
 * **The one OZM left in this app**, and it has to be. Everything else uses
 * OZFN, which is preferred because it leaves the enclosing macro visible to
 * Clang -- but OZFN is wrong here. INPUT_CALLBACK_DEFINE token-pastes its
 * callback into the object's name (`_input_callback__##name`, with `name`
 * defaulting to the callback), and OZFN's argument expands to `0` before
 * the paste. One would work; a second in this file would also become
 * `_input_callback__0` and Clang would reject the redefinition -- on the
 * AST-dump path, where a truncated dump silently costs ivar ownership
 * facts. Zephyr's INPUT_CALLBACK_DEFINE_NAMED is the way out if a second
 * one is ever needed here.
 */
OZM(
	INPUT_CALLBACK_DEFINE, NULL,
	^(struct input_event *evt, void *user_data) {
	  ARG_UNUSED(user_data);
	  [[PXKeyboard sharedInstance] handleInputEvent:evt];
	},
	NULL);

static PXKeyboard *sSharedKeyboard;

@implementation PXKeyboard

+ (void)initialize
{
	sSharedKeyboard = [[PXKeyboard alloc] init];
}

+ (instancetype)sharedInstance
{
	return sSharedKeyboard;
}

- (id)init
{
	self = [super init];
	if (self) {
		OZLog("PXKeyboard: initialized");
	}
	return self;
}

- (void)handleInputEvent:(struct input_event *)evt
{
	if (evt->type != INPUT_EV_KEY) {
		return;
	}

	struct msg_input msg;
	BOOL isLong = NO;

	switch (evt->code) {
	/* Raw presses, from the board's gpio-keys node. */
	case INPUT_KEY_0:
		msg.key = PX_KEY_P;
		break;
	case INPUT_KEY_1:
		msg.key = PX_KEY_X;
		break;
	case INPUT_KEY_2:
		msg.key = PX_KEY_K;
		break;
	case INPUT_KEY_3:
		msg.key = PX_KEY_B;
		break;
	/* Long presses, from the longpress node in app.overlay. */
	case INPUT_KEY_M:
		msg.key = PX_KEY_P;
		isLong = YES;
		break;
	case INPUT_KEY_N:
		msg.key = PX_KEY_X;
		isLong = YES;
		break;
	case INPUT_KEY_Y:
		msg.key = PX_KEY_K;
		isLong = YES;
		break;
	case INPUT_KEY_Z:
		msg.key = PX_KEY_B;
		isLong = YES;
		break;
	default:
		return;
	}

	msg.type = isLong ? (evt->value ? PX_INPUT_LONG_DOWN : PX_INPUT_LONG_UP)
			  : (evt->value ? PX_INPUT_DOWN : PX_INPUT_UP);

	int ret = zbus_chan_pub(&chan_input, &msg, K_MSEC(50));
	if (ret < 0) {
		OZLog("PXKeyboard: publish failed: %d", ret);
	}
}

- (int)getDescription:(char *)buf maxLength:(size_t)maxLen
{
	return snprintk(buf, maxLen, "<PXKeyboard>");
}

@end
