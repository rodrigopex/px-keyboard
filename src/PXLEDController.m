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
 *
 * It also owns the counted bursts -- the passkey and the bond-erase
 * confirmation -- and blinks them on the indicator itself: the status
 * animation pauses, the LED stays dark for PX_BURST_LEAD_MS, the burst
 * runs, and the current status is re-applied when it ends. One LED carries everything, on every board.
 *
 * Bursts used to go to led1 on its own GPIO. That breaks on the nRF54L15
 * DK, whose pwm-led0 alias drives P1.10 -- led1's pin -- because its PWM
 * cannot reach led0 at all: the PWM owned the pin and the passkey never
 * showed. Sharing the indicator works on any board with no per-board case.
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

/** @brief Blink half-period, for an indicator that is only on/off. */
#define PX_BLINK_MS 500

/** @brief Breath tick, and the level added per tick, for a dimmable one. */
#define PX_BREATH_MS   40
#define PX_BREATH_STEP 16

/**
 * @brief Dark lead-in before a burst's first blink.
 *
 * Without it the count starts straight out of the breath, and the last
 * fading breath reads as the first blink. Two seconds of off separates
 * "status" from "count" unambiguously.
 */
#define PX_BURST_LEAD_MS 2000

/** @brief Full brightness, matching PWMOutput's level range. */
#define PX_BREATH_MAX 255

/*
 * The hoisted timer block reaches the controller through the timer's own
 * user-data slot and does nothing else -- a block that captures is rejected
 * by the static bar, and user data is the same channel Zephyr's own C
 * callbacks use.
 *
 * The controller rather than the indicator, for two reasons. It keeps the
 * animation state in ivars instead of file-scope volatiles, and it gives
 * the send a concrete declared type: the static subset resolves a receiver
 * from its declaration, so a bare `id` here leaves it with the `void *`
 * that `k_timer_user_data_get` returns and no way to find the selector.
 *
 * OZFN rather than OZM (objective-z #300): OZM hid the whole invocation
 * from Clang, so `sIndicatorTimer` needed a hand-written
 * `#ifdef __OBJC__ static struct k_timer sIndicatorTimer; #endif` for the
 * `k_timer_stop`/`k_timer_start` below. OZFN hides only the block, so
 * K_TIMER_DEFINE expands on both sides and declares it on both.
 */

K_TIMER_DEFINE(sIndicatorTimer, OZFN(^(struct k_timer *timer) {
		 PXLEDController *controller =
			 (__bridge PXLEDController *)k_timer_user_data_get(timer);
		 [controller indicate];
	       }),
	       NULL);

/*
 * The only place BLE state becomes indicator state.
 *
 * Async, and that is not a preference. A synchronous listener runs in
 * whatever context published, and chan_ble_link is published from the
 * Bluetooth connection callbacks -- which run on the BT RX thread, 1200
 * bytes by default. Going `zbus_chan_pub` -> listener -> -setLEDStatus: ->
 * k_timer_stop on that stack overflowed it into the MPU guard and faulted
 * inside z_abort_timeout, right after logging "solid".
 *
 * The first version of this was synchronous, justified as "nothing below it
 * blocks". That was true and beside the point: the cost of a synchronous
 * listener is the publisher's *stack*, not just its latency. An indicator
 * has no deadline, so the work queue hop costs nothing that matters.
 */
/*
 * Same user-data channel for the burst. Its own timer rather than a mode of
 * the indicator's, so a burst's period never disturbs the breath's.
 */
K_TIMER_DEFINE(sBurstTimer, OZFN(^(struct k_timer *timer) {
		 PXLEDController *controller =
			 (__bridge PXLEDController *)k_timer_user_data_get(timer);
		 [controller burstStep];
	       }),
	       NULL);

/*
 * -setLEDStatus: runs on the system workqueue, -blink:periodMs: on the BT
 * RX thread, and both timers expire in ISR context. All four touch the same
 * LED and the same two timers, so each takes this for the whole of its
 * work.
 */
static struct k_spinlock sLEDLock;

ZBUS_ASYNC_LISTENER_DEFINE(alis_led_status,
			   OZFN(^(const struct zbus_channel *chan, const void *message) {
			     const struct msg_ble_link *link = message;
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
			   }));

ZBUS_CHAN_ADD_OBS(chan_ble_link, alis_led_status, 3);

static PXLEDController *sSharedLEDController;

@implementation PXLEDController {
	id<PXToggleable> _indicator;
	BOOL _dimmable;
	int _status;
	uint8_t _breathLevel;
	int8_t _breathDelta;
	int _burstTogglesLeft;
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

		_breathLevel = 0;
		_breathDelta = PX_BREATH_STEP;

		_indicator = [[PWMOutput alloc] initWithDTSpec:&kPwmLed0Spec];

		if (_indicator == nil && kLed0Spec.port) {
			_indicator = [[GPIOOutput alloc] initWithDTSpec:&kLed0Spec flags:0];
		}

		/*
		 * The static type says PXToggleable, so brightness support is
		 * only knowable at runtime.
		 */
		_dimmable = [_indicator conformsToProtocol:@protocol(PXDimmable)];
		_burstTogglesLeft = 0;

		k_timer_user_data_set(&sIndicatorTimer, (__bridge void *)self);
		k_timer_user_data_set(&sBurstTimer, (__bridge void *)self);

		_status = PX_LED_STATUS_OFF;
		OZLog("PXLEDController: initialized (%@)", _indicator);
	}
	return self;
}

- (void)setLEDStatus:(enum px_led_status)status
{
	BOOL applied = NO;
	k_spinlock_key_t key = k_spin_lock(&sLEDLock);

	if (_status != status) {
		_status = status;

		/* During a burst, the new status waits for it to end. */
		if (_burstTogglesLeft <= 0) {
			[self applyStatus];
			applied = YES;
		}
	}

	k_spin_unlock(&sLEDLock, key);

	/*
	 * Logged here, after the unlock and on the workqueue, never inside
	 * -applyStatus. OZLog is a synchronous UART print, about 2 ms for
	 * one line at 115200 baud. When the burst timer re-applied the status,
	 * that print ran in ISR context with sLEDLock's interrupts masked,
	 * and it held off the BLE controller's radio ISR long enough to trip
	 * lll_peripheral.c's EVENT_OVERHEAD_START_US assertion (2104 us).
	 */
	if (!applied || _indicator == nil) {
		return;
	}

	switch (status) {
	case PX_LED_STATUS_OFF:
		OZLog("PXLEDController: off");
		break;
	case PX_LED_STATUS_BLINK:
		OZLog("PXLEDController: %s", _dimmable ? "breathing" : "blinking");
		break;
	case PX_LED_STATUS_ON:
		OZLog("PXLEDController: solid");
		break;
	}
}

/**
 * Drive the indicator from _status. Called with sLEDLock held, and from
 * the burst timer's ISR, so it must stay short: no logging here.
 */
- (void)applyStatus
{
	k_timer_stop(&sIndicatorTimer);

	if (_indicator == nil) {
		return;
	}

	switch (_status) {
	case PX_LED_STATUS_OFF:
		[_indicator setActive:NO];
		break;

	case PX_LED_STATUS_BLINK:
		[_indicator setActive:NO];
		_breathLevel = 0;
		_breathDelta = PX_BREATH_STEP;

		if (_dimmable) {
			k_timer_start(&sIndicatorTimer, K_MSEC(PX_BREATH_MS), K_MSEC(PX_BREATH_MS));
		} else {
			k_timer_start(&sIndicatorTimer, K_MSEC(PX_BLINK_MS), K_MSEC(PX_BLINK_MS));
		}
		break;

	case PX_LED_STATUS_ON:
		[_indicator setActive:YES];
		break;
	}
}

- (void)blink:(unsigned int)count periodMs:(int)periodMs
{
	if (_indicator == nil) {
		return;
	}

	k_spinlock_key_t key = k_spin_lock(&sLEDLock);

	/* Restarts rather than queues, so the newest burst wins. */
	k_timer_stop(&sBurstTimer);
	k_timer_stop(&sIndicatorTimer);
	[_indicator setActive:NO];
	_burstTogglesLeft = (int)(count * 2U);
	k_timer_start(&sBurstTimer, K_MSEC(PX_BURST_LEAD_MS), K_MSEC(periodMs));

	k_spin_unlock(&sLEDLock, key);
}

- (void)burstStep
{
	k_spinlock_key_t key = k_spin_lock(&sLEDLock);

	if (_burstTogglesLeft <= 0) {
		k_timer_stop(&sBurstTimer);
		[_indicator setActive:NO];
		[self applyStatus];
	} else {
		[_indicator toggle];
		_burstTogglesLeft = _burstTogglesLeft - 1;
	}

	k_spin_unlock(&sLEDLock, key);
}

- (void)indicate
{
	if (_dimmable) {
		int level = _breathLevel + _breathDelta;

		if (level >= PX_BREATH_MAX) {
			level = PX_BREATH_MAX;
			_breathDelta = -PX_BREATH_STEP;
		} else if (level <= 0) {
			level = 0;
			_breathDelta = PX_BREATH_STEP;
		}

		_breathLevel = level;

		[(id<PXDimmable>)_indicator setLevel:(uint8_t)level];
	} else {
		[_indicator toggle];
	}
}

- (int)getDescription:(char *)buf maxLength:(size_t)maxLen
{
	static const char *const kStatusNames[] = {"off", "pulsing", "solid"};

	return snprintk(buf, maxLen, "<PXLEDController: %s indicator, %s>",
			_dimmable ? "dimmable" : "on/off", kStatusNames[_status]);
}

@end
