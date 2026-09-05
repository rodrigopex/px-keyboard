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
#import "PXKeyboard.h"

#include <string.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/services/bas.h>
#include <zephyr/bluetooth/uuid.h>
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
OZM(ZBUS_ASYNC_LISTENER_DEFINE, alis_ble_keys,
    ^(const struct zbus_channel *chan, const void *message) {
	const struct msg_keys *keys = message;
	[[PXBLEController sharedInstance] handleLongMask:keys->long_mask];
});

ZBUS_OBS_DECLARE(alis_ble_keys)

ZBUS_CHAN_ADD_OBS(chan_keys, alis_ble_keys, 3);

/* ---- Advertising data ---- */

static const struct bt_data ad[] = {
	BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
	BT_DATA_BYTES(BT_DATA_UUID16_ALL, BT_UUID_16_ENCODE(BT_UUID_HIDS_VAL),
		      BT_UUID_16_ENCODE(BT_UUID_BAS_VAL)),
};

static const struct bt_data sd[] = {
	BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

/* ---- Connection callbacks ---- */

static void connected(struct bt_conn *conn, uint8_t err)
{
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
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	printk("Disconnected: %s (reason 0x%02x)\n", addr, reason);

	if (sCurrentConn) {
		bt_conn_unref(sCurrentConn);
		sCurrentConn = NULL;
	}

	[[PXBLEController sharedInstance] onDisconnected];
}

/*
 * Advertising restarts here rather than in `disconnected`. There, the
 * connection object still exists and `bt_le_adv_start` returns -ENOMEM --
 * observed on hardware as "Advertising failed to start (err -12)", after
 * which the device was invisible until reset. Zephyr's own
 * `bt_conn_cb.disconnected` documentation points at this callback for the
 * purpose.
 */
static void recycled(void)
{
	[[PXBLEController sharedInstance] onConnectionRecycled];
}

static void security_changed(struct bt_conn *conn, bt_security_t level,
			     enum bt_security_err err)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

	if (!err) {
		printk("Security changed: %s level %u\n", addr, level);
	} else {
		printk("Security failed: %s level %u err %d\n", addr, level, err);
	}
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
	.connected = connected,
	.disconnected = disconnected,
	.recycled = recycled,
	.security_changed = security_changed,
};

/* ---- Pairing ---- */

static void auth_cancel(struct bt_conn *conn)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	printk("Pairing cancelled: %s\n", addr);
}

static struct bt_conn_auth_cb auth_cb = {
	.cancel = auth_cancel,
};

/*
 * Pairing outcome. Without these, a rejected pairing shows only as
 * `security_changed` reporting a level and an error code, which says that
 * it failed but not what the peer objected to.
 */
static void pairing_complete(struct bt_conn *conn, bool bonded)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	printk("Pairing complete: %s (bonded %d)\n", addr, bonded);
}

static void pairing_failed(struct bt_conn *conn, enum bt_security_err reason)
{
	char addr[BT_ADDR_LE_STR_LEN];

	bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));
	printk("Pairing failed: %s (reason %d)\n", addr, reason);
}

static struct bt_conn_auth_info_cb auth_info_cb = {
	.pairing_complete = pairing_complete,
	.pairing_failed = pairing_failed,
};

/* ---- BT ready ---- */

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

- (id)init
{
	self = [super init];
	if (self) {
		_lastLongMask = 0;
		_advertising = NO;

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
	int err = bt_le_adv_start(BT_LE_ADV_CONN_FAST_1, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));

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
	printk("Unpair all devices\n");

	/*
	 * bt_unpair() disconnects the peer itself -- unpair() in
	 * deps/zephyr/subsys/bluetooth/host/hci_core.c looks the connection
	 * up and calls bt_conn_disconnect() before clearing the keys. So
	 * there is nothing to wait for here: the disconnected callback
	 * re-advertises, and if there was no link the branch below does.
	 */
	int err = bt_unpair(BT_ID_DEFAULT, BT_ADDR_LE_ANY);
	if (err) {
		printk("bt_unpair failed (err %d)\n", err);
		return;
	}

	/*
	 * Only when there was no link to drop. Where there was, `bt_unpair`
	 * disconnected it, and advertising restarts from `recycled` once the
	 * connection object is actually free -- starting it here would hit
	 * the same -ENOMEM.
	 */
	if (!sCurrentConn) {
		[self startAdvertising];
	}
}

- (int)cDescription:(char *)buf maxLength:(size_t)maxLen
{
	static const char *const kStateNames[] = {"idle", "advertising", "connected"};

	return snprintk(buf, maxLen, "<PXBLEController: %s, linked=%d, long=0x%02x>",
			kStateNames[[self state]], sCurrentConn != NULL, _lastLongMask);
}

@end
