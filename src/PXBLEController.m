/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXBLEController.m
 * @brief Link state machine: idle -> advertising -> connected, plus the
 *        low-level BLE callbacks, advertising, pairing, and the four
 *        long-press gestures.
 */
#import "PXBLEController.h"
#import "GPIOOutput.h"
#import "PXKeyboard.h"

#include <string.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/services/bas.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/random/random.h>
#include <zephyr/settings/settings.h>
#include <zephyr/sys/printk.h>
#include <zephyr/types.h>

static struct bt_conn *sCurrentConn;

ZBUS_CHAN_DEFINE(chan_ble_link, struct msg_ble_link, NULL, NULL, ZBUS_OBSERVERS_EMPTY,
		 ZBUS_MSG_INIT(.state = PX_BLE_STATE_IDLE));

/*
 * Async rather than a plain listener: -forgetBond reaches bt_unpair, which
 * deletes settings keys and so touches flash. That belongs on a work queue,
 * not on the input-subsystem callback's thread. If the few milliseconds ever
 * show as button lag, zbus_async_listener_set_work_queue() moves it off the
 * system work queue.
 */
ZBUS_ASYNC_LISTENER_DEFINE(alis_ble_keys,
			   OZFN(^(const struct zbus_channel *chan, const void *message) {
			     const struct msg_keys *keys = message;
			     [[PXBLEController sharedInstance] handleLongMask:keys->long_mask];
			   }));

ZBUS_CHAN_ADD_OBS(chan_keys, alis_ble_keys, 3);

/* ---- Advertising data ---- */

static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	/*
	 * The appearance, so a host shows a keyboard rather than a generic
	 * device while scanning.
	 *
	 * `CONFIG_BT_DEVICE_APPEARANCE=961` on its own does *not* do this: it
	 * fills the GAP Appearance characteristic, which a host reads over
	 * GATT only after connecting -- by which point the icon beside the
	 * name, and in the pairing prompt, has already been chosen. It has to
	 * be in the advertisement to reach a scanner.
	 *
	 * Little-endian, so 961 (0x03C1) is 0xC1, 0x03. Written from the
	 * Kconfig value rather than as two literals, so there is one place
	 * that says what this device claims to be.
	 */
	BT_DATA_BYTES(BT_DATA_GAP_APPEARANCE, (CONFIG_BT_DEVICE_APPEARANCE & 0xff),
		      (CONFIG_BT_DEVICE_APPEARANCE >> 8)),
	BT_DATA_BYTES(BT_DATA_UUID16_ALL, BT_UUID_16_ENCODE(BT_UUID_HIDS_VAL),
		      BT_UUID_16_ENCODE(BT_UUID_BAS_VAL)),
};

static const struct bt_data sd[] = {
	BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

/**
 * @brief Advertising parameters, spelled out so the identity can be chosen.
 *
 * The values are BT_LE_ADV_CONN_FAST_1's, and that macro is what this would
 * otherwise be -- but BT_LE_ADV_PARAM_INIT pins `.id = BT_ID_DEFAULT`
 * (bluetooth.h:1100), and advertising on the default identity is precisely
 * what -forgetBond cannot work with: bt_id_reset() refuses BT_ID_DEFAULT.
 *
 * So this is not const, and `.id` is resolved once in bt_ready() -- to
 * identity 1 where the stack gave us one, and left at BT_ID_DEFAULT where it
 * did not.
 */
static struct bt_le_adv_param sAdvParam = {
	.id = BT_ID_DEFAULT,
	.sid = 0,
	.secondary_max_skip = 0,
	.options = BT_LE_ADV_OPT_CONN,
	.interval_min = BT_GAP_ADV_FAST_INT_MIN_1,
	.interval_max = BT_GAP_ADV_FAST_INT_MAX_1,
	.peer = NULL,
};

/** @brief The identity -forgetBond rotates, and the only one we ever bond on. */
#define PX_BT_IDENTITY 1

/* ---- Connection callbacks ---- */

/*
 * Written as blocks in the initializer itself, via OZFN (objective-z
 * #300). These are registered once and called from nowhere else, so a
 * named function bought only a second place to look; the body now sits at
 * the field that registers it.
 *
 * OZM cannot reach these: BT_CONN_CB_DEFINE takes only the *name*, and the
 * callbacks are in a designated initializer after the `=` -- not macro
 * arguments. OZFN hides one expression, so it can.
 *
 * Each block captures nothing. `sCurrentConn` is file scope, which the
 * static bar permits and does not count as a capture, and the controller
 * is reached through +sharedInstance the way every hoisted block reaches
 * its object.
 */
BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected = OZFN(^(struct bt_conn *conn, uint8_t err) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	  if (err) {
		  printk("Failed to connect to %s (err 0x%02x)\n", addr, err);
		  return;
	  }

	  printk("Connected: %s\n", addr);

	  if (sCurrentConn) {
		  bt_conn_unref(sCurrentConn);
	  }
	  sCurrentConn = bt_conn_ref(conn);

	  if (bt_conn_set_security(conn, BT_SECURITY_L2)) {
		  printk("Failed to set security\n");
	  }

	  [[PXBLEController sharedInstance] onConnected];
	}),

	.disconnected = OZFN(^(struct bt_conn *conn, uint8_t reason) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	  printk("Disconnected: %s (reason 0x%02x)\n", addr, reason);

	  if (sCurrentConn) {
		  bt_conn_unref(sCurrentConn);
		  sCurrentConn = NULL;
	  }

	  [[PXBLEController sharedInstance] onDisconnected];
	}),

	/*
	 * Advertising restarts here rather than in `.disconnected`. There the
	 * connection object still exists and `bt_le_adv_start` returns
	 * -ENOMEM -- observed on hardware as "Advertising failed to start
	 * (err -12)", after which the device was invisible until reset.
	 * Zephyr's own `bt_conn_cb.disconnected` documentation points at this
	 * callback for the purpose.
	 */
	.recycled = OZFN(^(void) {
	  [[PXBLEController sharedInstance] onConnectionRecycled];
	}),

	.security_changed = OZFN(^(struct bt_conn *conn, bt_security_t level,
				   enum bt_security_err err) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	  if (!err) {
		  printk("Security changed: %s level %u\n", addr, level);
		  return;
	  }

	  printk("Security failed: %s level %u err %d\n", addr, level, err);

	  /*
	   * The mirror of -forgetBond: the *host* dropped its bond, ours is
	   * still here, and so encryption cannot be established with a key
	   * only one side holds. Nothing in the stack cleans this up -- the
	   * host keeps the connection, unencrypted, and keeps its keys
	   * (hci_core.c:2243-2262), so the link is useless until someone
	   * deletes something. Dropping our side is what lets the host pair
	   * again on its next attempt.
	   *
	   * The idiom, and the reason this is safe to call from here, is
	   * Zephyr's own: samples/bluetooth/cap_initiator does the same in
	   * its security_changed, and smp.c:1948-1957 guards the reentrancy.
	   */
	  if (err == BT_SECURITY_ERR_PIN_OR_KEY_MISSING) {
		  printk("Peer lost its bond; dropping ours\n");

		  int unpair_err = bt_unpair(sAdvParam.id, bt_conn_get_dst(conn));
		  if (unpair_err) {
			  printk("bt_unpair failed (err %d)\n", unpair_err);
		  }
	  }
	}),
};

/* ---- Pairing ---- */

/* ---- Passkey display: blink the count on led1 ---- */

/**
 * @brief Blink count range, which is also the passkey range.
 *
 * The passkey is the blink count itself: `0000%02u` of a number in
 * PX_PASSKEY_MIN..PX_PASSKEY_MAX, so 7 blinks means typing `000007`. Six
 * digits because that is what BLE requires; the leading zeros are what let
 * a two-digit count fill it.
 *
 * The floor is 3, not 0. A count of zero blinks nothing, which reads
 * exactly like a board that failed to start the sequence; one or two are
 * short enough to be missed by someone who looked up a moment late. Three
 * is the smallest count that is unambiguously a count.
 *
 * **This is far weaker than a full passkey, deliberately, and the floor
 * costs a little more of it.** Passkey Entry defeats a man in the middle
 * because six digits are unpredictable; across 3..10 there are eight
 * values, so an attacker has a one-in-eight chance per attempt -- against
 * eleven before the floor, and 10^6 for the mechanism as designed. It is
 * still a real improvement on the fixed key it replaced, which was a
 * certainty. What it buys is a passkey readable off a board with no
 * screen, and readable *reliably*, which the zero was not.
 */
#define PX_PASSKEY_MIN 3U
#define PX_PASSKEY_MAX 10U

/**
 * @brief Half-period of one blink, so a count of N takes N*2*this.
 *
 * Named for the passkey specifically: PXLEDController has its own
 * PX_BLINK_MS, and every .m here is spliced into one translation unit, so
 * an unqualified name collides.
 */
#define PX_PASSKEY_BLINK_MS 250

/**
 * @brief Bond-erase confirmation: a burst on the same led1.
 *
 * Eight blinks, and deliberately three times faster than the passkey's 250.
 * Both bursts share one LED, so the period is what tells them apart -- a
 * count alone would not, given the passkey can itself be eight.
 */
#define PX_ERASE_BLINKS   8
#define PX_ERASE_BLINK_MS 80

static const struct gpio_dt_spec kLed1Spec = GPIO_DT_SPEC_GET(DT_ALIAS(led1), gpios);

/*
 * File scope rather than captured: a hoisted block takes no captures, and
 * the static bar does not count a file-scope variable as one. Same channel
 * PXLEDController's own timer block uses.
 *
 * Named for the burst rather than the passkey now that two callers arm it:
 * `.passkey_display` counts out the passkey, and `.bond_deleted` confirms an
 * erase.
 */
static GPIOOutput *sBurstLed;
static volatile int sBurstTogglesLeft;

/*
 * Blinking cannot happen in the callback that wants it. `.passkey_display`
 * runs on the BT RX thread during SMP, and sleeping there for up to five
 * seconds would stall the pairing it is part of -- on the same 2048-byte
 * stack that already overflowed once. So the callback only arms this, and
 * the timer does the work.
 */
K_TIMER_DEFINE(sBurstTimer, OZFN(^(struct k_timer *timer) {
		 ARG_UNUSED(timer);

		 if (sBurstTogglesLeft <= 0) {
			 k_timer_stop(&sBurstTimer);
			 [sBurstLed setActive:NO];
			 return;
		 }

		 [sBurstLed toggle];
		 sBurstTogglesLeft = sBurstTogglesLeft - 1;
	       }),
	       NULL);

/**
 * @brief Arm the burst: @p blinks on/off pairs at @p periodMs each half.
 *
 * Restarts rather than queues, so the newest burst wins. That is the right
 * rule for the two callers: an erase during pairing has just invalidated the
 * passkey being counted out, so replacing it mid-count is the honest signal.
 */
static void px_blink_burst(unsigned int blinks, int periodMs)
{
	if (sBurstLed == nil) {
		return;
	}

	k_timer_stop(&sBurstTimer);
	[sBurstLed setActive:NO];
	sBurstTogglesLeft = (int)(blinks * 2U);
	k_timer_start(&sBurstTimer, K_MSEC(periodMs), K_MSEC(periodMs));
}

/**
 * @brief The pairing passkey, generated per pairing.
 *
 * Drawn fresh for every pairing from the hardware RNG
 * (CONFIG_ENTROPY_NRF5_RNG), in PX_PASSKEY_MIN..PX_PASSKEY_MAX, and shown
 * by blinking led1 that many times. Zephyr's note on CONFIG_BT_APP_PASSKEY --
 * "it is the responsibility of the application to use random and unique keys"
 * -- is why this replaced a fixed 555555; see PX_PASSKEY_MAX for how much of
 * that responsibility a range of eleven actually discharges.
 *
 * Returning BT_PASSKEY_RAND instead would restore a full six-digit random
 * passkey, at the cost of needing the console to read it.
 */

static struct bt_conn_auth_cb auth_cb = {
	/*
	 * Registering `.passkey_display` at all is what makes pairing possible
	 * here, not a nicety.
	 *
	 * With no auth callbacks beyond `.cancel`, `smp.c::get_io_capa` returns
	 * BT_SMP_IO_NO_INPUT_OUTPUT, so the only available method is Just Works --
	 * and Zephyr then *clears* the MITM bit rather than requesting it
	 * (smp.c:2936), so `CONFIG_BT_SMP_ENFORCE_MITM` has nothing to do with it.
	 * The host is what refuses: a keyboard that cannot authenticate is a
	 * keystroke-injection risk, so macOS rejected the pairing with
	 * BT_SECURITY_ERR_AUTH_REQUIREMENT and dropped the link.
	 *
	 * `passkey_display` alone earns BT_SMP_IO_DISPLAY_ONLY, which against a
	 * host's KeyboardDisplay selects Passkey Entry: this side shows six digits,
	 * the host's user types them. That is authenticated, and it is what a real
	 * BLE keyboard does -- the console is the display.
	 *
	 * All three callbacks are blocks in the initializer, via OZFN, like the
	 * connection callbacks; each captures nothing.
	 *
	 * `.app_passkey` was a named function until objective-z #303, and not by
	 * choice: it returns `uint32_t`, and oz_static carried no block return
	 * type. Written without one it inferred `int`, which GCC rejects against
	 * this field; written with one -- `^uint32_t(struct bt_conn *conn)` --
	 * it dropped the return type *and* the parameter list, emitting
	 * `int f(void)` and leaving `conn` undeclared. Both are fixed, so the
	 * block form below is what the file now uses and the workaround is gone.
	 */
	.app_passkey = OZFN(^uint32_t(struct bt_conn *conn) {
	  ARG_UNUSED(conn);

	  /* Inclusive at both ends: eight values for 3..10. The modulo bias
	   * over 2^32 is immaterial next to the range being eight wide in the
	   * first place. */
	  return (uint32_t)(PX_PASSKEY_MIN +
			    sys_rand32_get() % (PX_PASSKEY_MAX - PX_PASSKEY_MIN + 1U));
	}),

	.passkey_display = OZFN(^(struct bt_conn *conn, unsigned int passkey) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	  printk("Pairing passkey for %s: %06u (%u blink(s) on led1)\n", addr, passkey, passkey);

	  /* Arm and return: the timer blinks, this thread does not. */
	  px_blink_burst(passkey, PX_PASSKEY_BLINK_MS);
	}),

	.cancel = OZFN(^(struct bt_conn *conn) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	  printk("Pairing cancelled: %s\n", addr);
	}),
};

static struct bt_conn_auth_info_cb auth_info_cb = {
	.pairing_complete = OZFN(^(struct bt_conn *conn, bool bonded) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	  printk("Pairing complete: %s (bonded %d)\n", addr, bonded);
	}),
	/*
	 * Pairing outcome. Without these, a rejected pairing shows only as
	 * `security_changed` reporting a level and an error code, which says that
	 * it failed but not what the peer objected to.
	 */
	.pairing_failed = OZFN(^(struct bt_conn *conn, enum bt_security_err reason) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	  printk("Pairing failed: %s (reason %d)\n", addr, reason);
	}),
	/*
	 * Fired by the stack from inside unpair() (hci_core.c:2155-2164), so it
	 * covers every route a bond can go: the sw3 gesture, the
	 * PIN-or-Key-Missing cleanup in `.security_changed`, and key-pool
	 * eviction. Confirming the erase here rather than at the gesture means
	 * the burst reports what actually happened.
	 *
	 * It is also why this callback is registered *after* bt_ready()'s
	 * one-time identity-0 cleanup: that cleanup would otherwise blink an
	 * erase on every boot.
	 */
	.bond_deleted = OZFN(^(uint8_t identity, const bt_addr_le_t *peer) {
	  char addr[BT_ADDR_LE_STR_LEN];

	  bt_addr_le_to_str(peer, addr, sizeof(addr));
	  printk("Bond deleted: %s (id %u)\n", addr, identity);

	  px_blink_burst(PX_ERASE_BLINKS, PX_ERASE_BLINK_MS);
	}),
};

/* ---- BT ready ---- */

/**
 * @brief Point advertising at identity PX_BT_IDENTITY, creating it if needed.
 *
 * Two things, both once per boot.
 *
 * First, drop any bond on identity 0. Nothing bonds there any more, but a
 * build from before this identity existed did, and that bond would sit in NVS
 * holding one of the two CONFIG_BT_MAX_PAIRED slots for a peer we will never
 * talk to again. Costs nothing when there is none: bt_unpair iterates the
 * bonds it finds, so with none it writes no flash.
 *
 * Second, make sure identity 1 exists. bt_id_create() with a NULL address is
 * the one case the stack persists for us (bluetooth.h:438-460) -- it needs
 * bt_enable() and settings_load() to have run first, which is why this is
 * here and not in -init -- so the address survives a reboot, and step 5 of
 * the verification checks exactly that.
 *
 * On failure this leaves sAdvParam.id at BT_ID_DEFAULT. The keyboard then
 * behaves as it did before identity rotation existed: it still pairs, and
 * -forgetBond still clears our keys, but a host will need "Forget This
 * Device" before it can pair again. Degrading beats not advertising.
 */
static void resolve_identity(void)
{
	bt_addr_le_t addrs[CONFIG_BT_ID_MAX];
	size_t count = ARRAY_SIZE(addrs);
	char addr_str[BT_ADDR_LE_STR_LEN];

	int err = bt_unpair(BT_ID_DEFAULT, NULL);
	if (err) {
		printk("Clearing legacy id-0 bonds failed (err %d)\n", err);
	}

	bt_id_get(addrs, &count);

	if (count <= PX_BT_IDENTITY) {
		err = bt_id_create(NULL, NULL);
		if (err < 0) {
			printk("bt_id_create failed (err %d), staying on id 0\n", err);
			return;
		}

		count = ARRAY_SIZE(addrs);
		bt_id_get(addrs, &count);
	}

	/*
	 * Re-checked rather than assumed. bt_id_get reports how many
	 * identities it actually copied, and pointing the advertisement at a
	 * slot the stack does not have would fail bt_le_adv_start with
	 * -EINVAL -- leaving the keyboard silent, which is worse than leaving
	 * it on identity 0.
	 */
	if (count <= PX_BT_IDENTITY) {
		printk("Identity %u missing, staying on id 0\n", PX_BT_IDENTITY);
		return;
	}

	sAdvParam.id = PX_BT_IDENTITY;

	bt_addr_le_to_str(&addrs[PX_BT_IDENTITY], addr_str, sizeof(addr_str));
	printk("Identity %u: %s\n", PX_BT_IDENTITY, addr_str);
}

static void bt_ready(int err)
{
	if (err) {
		printk("Bluetooth init failed (err %d)\n", err);
		return;
	}

	printk("Bluetooth initialized\n");

	if (IS_ENABLED(CONFIG_SETTINGS)) {
		settings_load();
	}

	/*
	 * Everything below has to happen after settings_load() -- it is what
	 * restores the identity created on an earlier boot -- and before
	 * bt_conn_auth_info_cb_register(), so that the cleanup's `bond_deleted`
	 * does not blink an erase burst on every boot.
	 */
	resolve_identity();

	bt_conn_auth_cb_register(&auth_cb);
	bt_conn_auth_info_cb_register(&auth_info_cb);

	[[PXBLEController sharedInstance] onBTReady];
}

/* ---- PXBLEController ---- */

static PXBLEController *sSharedController;

@implementation PXBLEController {
	/*
	 * One selector per key, dispatched on the rising edge of that key's
	 * long-press bit. Filled in -init rather than as a static initializer,
	 * so @selector() is evaluated at runtime.
	 */
	SEL _gestures[PX_KEY_COUNT];
	uint8_t _lastLongMask;
	BOOL _advertising;
}

+ (void)initialize
{
	sSharedController = [[PXBLEController alloc] init];
}

+ (instancetype)sharedInstance
{
	return sSharedController;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_lastLongMask = 0;
		_advertising = NO;

		if (kLed1Spec.port) {
			sBurstLed = [[GPIOOutput alloc] initWithDTSpec:&kLed1Spec flags:0];
		}

		_gestures[PX_KEY_P] = @selector(toggleAdvertising);
		_gestures[PX_KEY_X] = @selector(disconnectLink);
		_gestures[PX_KEY_K] = @selector(reportBatteryLevel);
		_gestures[PX_KEY_B] = @selector(forgetBond);

		for (int key = 0; key < PX_KEY_COUNT; key++) {
			oz_assert([self respondsToSelector:_gestures[key]]);
		}

		OZLog("PXBLEController: initialized");
	}
	return self;
}

- (void)start
{
	int err = bt_enable(bt_ready);
	if (err) {
		OZLog("PXBLEController: BT enable failed (%d)", err);
	}
}

- (enum px_ble_state)state
{
	struct msg_ble_link msg = {.state = PX_BLE_STATE_IDLE};

	zbus_chan_read(&chan_ble_link, &msg, K_MSEC(50));

	return msg.state;
}

/** @brief Publish a transition; the LED controller observes the channel. */
- (void)publishState:(enum px_ble_state)state
{
	struct msg_ble_link msg = {.state = state};

	int ret = zbus_chan_pub(&chan_ble_link, &msg, K_MSEC(100));
	if (ret < 0) {
		OZLog("PXBLEController: state publish failed: %d", ret);
	}
}

- (void)onBTReady
{
	OZLog("PXBLEController: BT ready, start advertising");
	[self startAdvertising];
}

- (void)onConnected
{
	OZLog("PXBLEController: connected");
	_advertising = NO;
	[self publishState:PX_BLE_STATE_CONNECTED];
}

- (void)onDisconnected
{
	OZLog("PXBLEController: disconnected");
	_advertising = NO;
	[self publishState:PX_BLE_STATE_IDLE];
}

- (void)onConnectionRecycled
{
	OZLog("PXBLEController: connection recycled, re-advertising");
	[self startAdvertising];
}

/* ---- Advertising ---- */

- (int)startAdvertising
{
	int err = bt_le_adv_start(&sAdvParam, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));

	if (err && err != -EALREADY) {
		printk("Advertising failed to start (err %d)\n", err);
		[self publishState:PX_BLE_STATE_IDLE];
		return err;
	}

	printk("Advertising started\n");
	_advertising = YES;
	[self publishState:PX_BLE_STATE_ADVERTISING];

	return 0;
}

- (int)stopAdvertising
{
	int err = bt_le_adv_stop();

	if (err) {
		printk("Advertising failed to stop (err %d)\n", err);
		return err;
	}

	printk("Advertising stopped\n");
	_advertising = NO;
	[self publishState:PX_BLE_STATE_IDLE];

	return 0;
}

/* ---- Gestures ---- */

- (void)handleLongMask:(uint8_t)longMask
{
	uint8_t rising = longMask & ~_lastLongMask;

	_lastLongMask = longMask;

	for (int key = 0; key < PX_KEY_COUNT; key++) {
		if (rising & BIT(key)) {
			OZLog("PXBLEController: gesture on key %d", key);
			[self performSelector:_gestures[key]];
		}
	}
}

- (void)toggleAdvertising
{
	if (_advertising) {
		[self stopAdvertising];
	} else {
		[self startAdvertising];
	}
}

- (void)disconnectLink
{
	if (!sCurrentConn) {
		OZLog("PXBLEController: no link to drop");
		return;
	}

	int err = bt_conn_disconnect(sCurrentConn, BT_HCI_ERR_REMOTE_USER_TERM_CONN);
	if (err) {
		printk("bt_conn_disconnect failed (err %d)\n", err);
	}
}

- (void)reportBatteryLevel
{
	/*
	 * No fuel gauge on this board, so this reports a fixed level. It is
	 * here to exercise the BAS characteristic the advertising data
	 * already claims.
	 */
	uint8_t level = 100;

	int err = bt_bas_set_battery_level(level);
	if (err) {
		printk("bt_bas_set_battery_level failed (err %d)\n", err);
		return;
	}

	OZLog("PXBLEController: battery level %u%%", level);
}

- (void)forgetBond
{
	printk("Forget bonds\n");

	/*
	 * Advertising has to stop first, and not as tidiness: bt_id_reset()
	 * returns -EBUSY while any advertising set is enabled on the identity
	 * it is asked to reset (id.c:1441-1451).
	 */
	if (_advertising) {
		[self stopAdvertising];
	}

	int err;

	if (sAdvParam.id == BT_ID_DEFAULT) {
		/*
		 * No second identity, so the keys are all that can go. The
		 * host keeps its bond and will need "Forget This Device"
		 * before it can pair again -- see resolve_identity().
		 */
		err = bt_unpair(BT_ID_DEFAULT, NULL);
		if (err) {
			printk("bt_unpair failed (err %d)\n", err);
		}
	} else {
		/*
		 * The whole gesture in one call: bt_id_reset() unpairs the
		 * identity, which disconnects the peer on the way, and then
		 * generates a fresh random static address for it
		 * (id.c:1453-1461).
		 *
		 * The new address is the point. Deleting our keys alone leaves
		 * the host holding a bond it cannot use, and neither macOS nor
		 * the Bluetooth spec has a way for us to ask it to let go --
		 * the next encryption attempt just fails with
		 * PIN-or-Key-Missing. Coming back on a different address
		 * sidesteps that: the host has never seen this device, so it
		 * pairs normally. Its old entry stays in the list, dead, and
		 * nothing on air can remove it.
		 */
		err = bt_id_reset(sAdvParam.id, NULL, NULL);
		if (err < 0) {
			printk("bt_id_reset failed (err %d)\n", err);
		} else {
			bt_addr_le_t addrs[CONFIG_BT_ID_MAX];
			size_t count = ARRAY_SIZE(addrs);
			char addr_str[BT_ADDR_LE_STR_LEN];

			bt_id_get(addrs, &count);
			bt_addr_le_to_str(&addrs[sAdvParam.id], addr_str, sizeof(addr_str));
			printk("Identity %u is now %s\n", sAdvParam.id, addr_str);
		}
	}

	/*
	 * Only when there was no link to drop. Where there was, the unpair
	 * inside either branch disconnected it, and advertising restarts from
	 * `recycled` once the connection object is actually free -- starting
	 * it here would hit the same -ENOMEM.
	 */
	if (!sCurrentConn) {
		[self startAdvertising];
	}
}

- (int)cDescription:(char *)buf maxLength:(size_t)maxLen
{
	static const char *const kStateNames[] = {"idle", "advertising", "connected"};
	unsigned int bonds = 0;

	bt_foreach_bond(sAdvParam.id, OZFN(^(const struct bt_bond_info *info, void *user_data) {
			  ARG_UNUSED(info);
			  unsigned int *bonds_count = user_data;
			  *bonds_count = *bonds_count + 1U;
			}),
			&bonds);

	/*
	 * The identity address is deliberately not here. It is 30 more
	 * characters into a buffer this has to share, and it is already
	 * printed at boot and on every reset, which is where it matters.
	 */
	return snprintk(buf, maxLen,
			"<PXBLEController: %s, linked=%d, long=0x%02x, id=%u, bonds=%u>",
			kStateNames[[self state]], sCurrentConn != NULL, _lastLongMask,
			sAdvParam.id, bonds);
}

@end
