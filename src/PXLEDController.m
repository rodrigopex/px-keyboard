/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXLEDController.m
 * @brief chan_ble_link -> indicator.
 *
 * The indicator is an id<PXToggleable>, chosen at init: the board's
 * pwm_led0 if &pwm0 came up, LED0 on plain GPIO otherwise. Because the
 * static type promises only PXToggleable, whether brightness is available
 * is a genuine runtime question -- so the pulsing state asks
 * -conformsToProtocol:@protocol(PXDimmable) and breathes or blinks
 * accordingly.
 */
#import "PXLEDController.h"
#import "PXDimmable.h"
#import "GPIOOutput.h"
#import "PWMOutput.h"
#import "PXBLEController.h"

#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/pwm.h>
#include <zephyr/kernel.h>

static const struct gpio_dt_spec kLed0Spec = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct pwm_dt_spec kPwmLed0Spec = PWM_DT_SPEC_GET(DT_ALIAS(pwm_led0));

/*
 * WORKAROUND (objective-z #288, see WORKAROUNDS.md): declared ahead of the
 * OZM blocks below. Left where the other three singletons keep theirs --
 * just above the @implementation -- it reached the C compiler as
 * `PXLEDController *` rather than `struct PXLEDController *`.
 */
static PXLEDController *sSharedLEDController;

/** @brief Blink half-period, for an indicator that is only on/off. */
#define PX_BLINK_MS 500

/** @brief Breath tick, and the level added per tick, for a dimmable one. */
#define PX_BREATH_MS   40
#define PX_BREATH_STEP 16

/** @brief Full brightness, matching PWMOutput's level range. */
#define PX_BREATH_MAX 255

/*
 * The hoisted timer block reaches the indicator through the timer's own
 * user-data slot, and its animation state through these file-scope
 * variables -- a block that captures is rejected by the static bar, and
 * file scope is the same channel Zephyr's own C callbacks use.
 */
static volatile BOOL sBreathes;
static volatile int sBreathLevel;
static volatile int sBreathDelta;

OZM(K_TIMER_DEFINE, sIndicatorTimer, ^(struct k_timer *timer) {
	id<PXToggleable> indicator = (__bridge id<PXToggleable>)k_timer_user_data_get(timer);

	if (!sBreathes) {
		[indicator toggle];
		return;
	}

	int level = sBreathLevel + sBreathDelta;

	if (level >= PX_BREATH_MAX) {
		level = PX_BREATH_MAX;
		sBreathDelta = -PX_BREATH_STEP;
	} else if (level <= 0) {
		level = 0;
		sBreathDelta = PX_BREATH_STEP;
	}

	sBreathLevel = level;

	[(id<PXDimmable>)indicator setLevel:(uint8_t)level];
}, NULL);

#ifdef __OBJC__
/* Discarded above on this side; the generated C gets the real definition. */
static struct k_timer sIndicatorTimer;
#endif

/*
 * The only place BLE state becomes indicator state. A plain synchronous
 * listener is right here: nothing below it blocks.
 */
OZM(ZBUS_LISTENER_DEFINE, lis_led_status, ^(const struct zbus_channel *chan) {
	const struct msg_ble_link *link = zbus_chan_const_msg(chan);
	enum px_led_status status = PX_LED_STATUS_OFF;

	switch (link->state) {
	case PX_BLE_STATE_ADVERTISING:
		status = PX_LED_STATUS_BLINK;
		break;
	case PX_BLE_STATE_CONNECTED:
		status = PX_LED_STATUS_ON;
		break;
	case PX_BLE_STATE_IDLE:
		status = PX_LED_STATUS_OFF;
		break;
	}

	[[PXLEDController sharedInstance] setLEDStatus:status];
});

ZBUS_OBS_DECLARE(lis_led_status)

ZBUS_CHAN_ADD_OBS(chan_ble_link, lis_led_status, 3);

/*
 * WORKAROUND (objective-z #288, see WORKAROUNDS.md): `id` rather than
 * `id<PXToggleable>`, with the protocol moved to the send sites below.
 *
 * The defect is positional -- an OZM block between an @interface and its
 * @implementation leaves the whole @implementation untranslated -- and the
 * ivar's type is not actually what triggers it. Spelling it `id` is what
 * happens to sidestep it here; it is not the explanation.
 */
@implementation PXLEDController {
	id _indicator;
	BOOL _dimmable;
	int _status;
}

+ (void)initialize
{
	sSharedLEDController = [[PXLEDController alloc] init];
}

+ (instancetype)sharedInstance
{
	return sSharedLEDController;
}

- (id)init
{
	self = [super init];
	if (self) {
		_indicator = [[PWMOutput alloc] initWithDTSpec:&kPwmLed0Spec];

		if (_indicator == nil && kLed0Spec.port) {
			_indicator = [[GPIOOutput alloc] initWithDTSpec:&kLed0Spec flags:0];
		}

		/*
		 * The static type says PXToggleable, so brightness support is
		 * only knowable at runtime.
		 */
		_dimmable = [_indicator conformsToProtocol:@protocol(PXDimmable)];

		k_timer_user_data_set(&sIndicatorTimer, (__bridge void *)_indicator);

		_status = PX_LED_STATUS_OFF;
		OZLog("PXLEDController: initialized (%@)", _indicator);
	}
	return self;
}

- (void)setLEDStatus:(enum px_led_status)status
{
	if (_status == status) {
		return;
	}
	_status = status;

	k_timer_stop(&sIndicatorTimer);

	if (_indicator == nil) {
		return;
	}

	switch (status) {
	case PX_LED_STATUS_OFF:
		[(id<PXToggleable>)_indicator setActive:NO];
		OZLog("PXLEDController: off");
		break;

	case PX_LED_STATUS_BLINK:
		[(id<PXToggleable>)_indicator setActive:NO];
		sBreathes = _dimmable;
		sBreathLevel = 0;
		sBreathDelta = PX_BREATH_STEP;

		if (_dimmable) {
			k_timer_start(&sIndicatorTimer, K_MSEC(PX_BREATH_MS),
				      K_MSEC(PX_BREATH_MS));
			OZLog("PXLEDController: breathing");
		} else {
			k_timer_start(&sIndicatorTimer, K_MSEC(PX_BLINK_MS),
				      K_MSEC(PX_BLINK_MS));
			OZLog("PXLEDController: blinking");
		}
		break;

	case PX_LED_STATUS_ON:
		[(id<PXToggleable>)_indicator setActive:YES];
		OZLog("PXLEDController: solid");
		break;
	}
}

- (int)cDescription:(char *)buf maxLength:(int)maxLen
{
	static const char *const kStatusNames[] = {"off", "pulsing", "solid"};

	return snprintk(buf, maxLen, "<PXLEDController: %s indicator, %s>",
			_dimmable ? "dimmable" : "on/off", kStatusNames[_status]);
}

@end
