/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXKeyboard.m
 * @brief Input subsystem -> chan_keys.
 *
 * The buttons arrive as two families of event codes. The raw ones
 * (INPUT_KEY_0..3) come straight from the gpio-keys node in the board
 * devicetree. The long-press ones (INPUT_KEY_M/N/Y/Z) come from the
 * zephyr,input-longpress node in app.overlay, which republishes a held key
 * under a second code after long-delay-ms and clears it on release. Both
 * families reach this one callback, and both fold into one message.
 */
#import "PXKeyboard.h"

#include <zephyr/dt-bindings/input/input-event-codes.h>

ZBUS_CHAN_DEFINE(chan_keys, struct msg_keys, NULL, NULL, ZBUS_OBSERVERS_EMPTY,
		 ZBUS_MSG_INIT(.mask = 0, .long_mask = 0));

/*
 * The callback is a block so the wiring reads as one unit, which means it
 * must reach its object the way every hoisted block does -- through the
 * singleton, never through a capture. OZM carries the block into the macro;
 * see include/oz_sdk/Foundation/OZMacro.h.
 */
OZM(INPUT_CALLBACK_DEFINE, NULL, ^(struct input_event *evt, void *user_data) {
	ARG_UNUSED(user_data);
	[[PXKeyboard sharedInstance] handleInputEvent:evt];
}, NULL);

static PXKeyboard *sSharedKeyboard;

@implementation PXKeyboard {
	uint8_t _mask;
	uint8_t _longMask;
}

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
		_mask = 0;
		_longMask = 0;
		OZLog("PXKeyboard: initialized");
	}
	return self;
}

- (uint8_t)mask
{
	return _mask;
}

- (uint8_t)longMask
{
	return _longMask;
}

- (void)handleInputEvent:(struct input_event *)evt
{
	if (evt->type != INPUT_EV_KEY) {
		return;
	}

	uint8_t bit;
	uint8_t *target;

	switch (evt->code) {
	/* Raw presses, from the board's gpio-keys node. */
	case INPUT_KEY_0:
		bit = BIT(PX_KEY_P);
		target = &_mask;
		break;
	case INPUT_KEY_1:
		bit = BIT(PX_KEY_X);
		target = &_mask;
		break;
	case INPUT_KEY_2:
		bit = BIT(PX_KEY_K);
		target = &_mask;
		break;
	case INPUT_KEY_3:
		bit = BIT(PX_KEY_B);
		target = &_mask;
		break;
	/* Long presses, from the longpress node in app.overlay. */
	case INPUT_KEY_M:
		bit = BIT(PX_KEY_P);
		target = &_longMask;
		break;
	case INPUT_KEY_N:
		bit = BIT(PX_KEY_X);
		target = &_longMask;
		break;
	case INPUT_KEY_Y:
		bit = BIT(PX_KEY_K);
		target = &_longMask;
		break;
	case INPUT_KEY_Z:
		bit = BIT(PX_KEY_B);
		target = &_longMask;
		break;
	default:
		return;
	}

	uint8_t updated = evt->value ? (*target | bit) : (*target & ~bit);

	if (updated == *target) {
		return;
	}

	*target = updated;

	struct msg_keys msg = {
		.mask = _mask,
		.long_mask = _longMask,
	};

	int ret = zbus_chan_pub(&chan_keys, &msg, K_MSEC(50));
	if (ret < 0) {
		OZLog("PXKeyboard: publish failed: %d", ret);
	}
}

- (int)cDescription:(char *)buf maxLength:(size_t)maxLen
{
	return snprintk(buf, maxLen, "<PXKeyboard: mask=0x%02x long=0x%02x>", _mask, _longMask);
}

@end
