/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXLEDController.m
 * @brief LED controller managing power LED and BLE status LED with blink
 * support.
 */
#import "PXLEDController.h"
#import "GPIOOutput.h"
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>

static const struct gpio_dt_spec kLed0Spec =
    GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);
static const struct gpio_dt_spec kLed1Spec =
    GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);
static const struct gpio_dt_spec kLed2Spec =
    GPIO_DT_SPEC_GET(DT_ALIAS(led2), gpios);
static const struct gpio_dt_spec kLed3Spec =
    GPIO_DT_SPEC_GET(DT_ALIAS(led3), gpios);

static GPIOOutput *sBLELed;

static void blink_expiry(struct k_timer *timer) {
  ARG_UNUSED(timer);
  if (sBLELed != nil) {
    [sBLELed toggle];
  }
}

static K_TIMER_DEFINE(sBLEBlinkTimer, blink_expiry, NULL);

@implementation PXLEDController {
  GPIOOutput *_powerLed;
  GPIOOutput *_bleLed;
  GPIOOutput *_led2;
  GPIOOutput *_led3;
  int _bleStatus;
}

- (id)init {
  self = [super init];
  if (self) {
    if (kLed0Spec.port) {
      _powerLed = [[GPIOOutput alloc] initWithDTSpec:&kLed0Spec flags:0];
    }
    if (kLed1Spec.port) {
      _bleLed = [[GPIOOutput alloc] initWithDTSpec:&kLed1Spec flags:0];
    }
    if (kLed2Spec.port) {
      _led2 = [[GPIOOutput alloc] initWithDTSpec:&kLed2Spec flags:0];
    }
    if (kLed3Spec.port) {
      _led3 = [[GPIOOutput alloc] initWithDTSpec:&kLed3Spec flags:0];
    }

    sBLELed = _bleLed;

    /* Power LED always on */
    if (_powerLed != nil) {
      [_powerLed setActive:YES];
    }

    _bleStatus = PX_BLE_STATUS_OFF;
    OZLog("PXLEDController: initialized");
  }
  return self;
}

- (void)setBLEStatus:(int)status {
  if (_bleStatus == status) {
    return;
  }
  _bleStatus = status;

  k_timer_stop(&sBLEBlinkTimer);

  if (_bleLed == nil) {
    return;
  }

  if (status == PX_BLE_STATUS_OFF) {
    [_bleLed setActive:NO];
    OZLog("PXLEDController: BLE OFF");
  } else if (status == PX_BLE_STATUS_ADVERTISING) {
    [_bleLed setActive:NO];
    k_timer_start(&sBLEBlinkTimer, K_MSEC(500), K_MSEC(500));
    OZLog("PXLEDController: BLE ADVERTISING (blink)");
  } else if (status == PX_BLE_STATUS_CONNECTED) {
    [_bleLed setActive:YES];
    OZLog("PXLEDController: BLE CONNECTED");
  }
}

@end
