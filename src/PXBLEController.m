/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXBLEController.m
 * @brief BLE state machine: idle -> advertising -> connected.
 *        Singleton created via +initialize (runs before main).
 *        Includes low-level BLE callbacks, advertising, and pairing.
 */
#import "PXBLEController.h"

#include <zephyr/types.h>
#include <string.h>
#include <zephyr/sys/printk.h>
#include <zephyr/kernel.h>
#include <zephyr/settings/settings.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>

static PXBLEController *sSharedController;
static struct bt_conn *sCurrentConn;

/* ---- Advertising data ---- */

static const struct bt_data ad[] = {
        BT_DATA_BYTES(BT_DATA_FLAGS,
                      (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
        BT_DATA_BYTES(BT_DATA_UUID16_ALL,
                      BT_UUID_16_ENCODE(BT_UUID_HIDS_VAL),
                      BT_UUID_16_ENCODE(BT_UUID_BAS_VAL)),
};

static const struct bt_data sd[] = {
        BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME,
                sizeof(CONFIG_BT_DEVICE_NAME) - 1),
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

        [[PXBLEController shared] onConnected];
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

        [[PXBLEController shared] onDisconnected];
}

static void security_changed(struct bt_conn *conn, bt_security_t level,
                             enum bt_security_err err)
{
        char addr[BT_ADDR_LE_STR_LEN];

        bt_addr_le_to_str(bt_conn_get_dst(conn), addr, sizeof(addr));

        if (!err) {
                printk("Security changed: %s level %u\n", addr, level);
        } else {
                printk("Security failed: %s level %u err %d\n",
                       addr, level, err);
        }
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
        .connected = connected,
        .disconnected = disconnected,
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

        [[PXBLEController shared] onBTReady];
}

/* ---- Helpers ---- */

static int start_advertising(void)
{
        int err;

        err = bt_le_adv_start(BT_LE_ADV_CONN_FAST_1,
                              ad, ARRAY_SIZE(ad),
                              sd, ARRAY_SIZE(sd));
        if (err) {
                printk("Advertising failed to start (err %d)\n", err);
        } else {
                printk("Advertising started\n");
        }

        return err;
}

static int unpair_all(void)
{
        int err;

        printk("Unpair all devices\n");

        if (sCurrentConn) {
                err = bt_conn_disconnect(sCurrentConn,
                                         BT_HCI_ERR_REMOTE_USER_TERM_CONN);
                if (err) {
                        printk("bt_conn_disconnect failed (err %d)\n", err);
                }
                while (sCurrentConn) {
                        k_msleep(50);
                }
                k_msleep(200);
        }

        err = bt_unpair(BT_ID_DEFAULT, BT_ADDR_LE_ANY);
        if (err) {
                printk("bt_unpair failed (err %d)\n", err);
        }

        return err;
}

/* ---- PXBLEController ---- */

@implementation PXBLEController {
    PXLEDController *_leds;
    int _state;
    BOOL _unpairing;
}

+ (void)initialize
{
    sSharedController = [[PXBLEController alloc] init];
}

+ (PXBLEController *)shared
{
    return sSharedController;
}

- (id)init
{
    self = [super init];
    if (self) {
        _leds = [[PXLEDController alloc] init];
        _state = 0;
        _unpairing = NO;
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

- (int)state
{
    return _state;
}

- (void)onBTReady
{
    OZLog("PXBLEController: BT ready, start advertising");
    start_advertising();
    _state = 1;
    [_leds setBLEStatus:1];
}

- (void)onConnected
{
    OZLog("PXBLEController: connected");
    _state = 2;
    [_leds setBLEStatus:2];
}

- (void)onDisconnected
{
    if (_unpairing) {
        OZLog("PXBLEController: disconnected (unpair in progress)");
        return;
    }
    OZLog("PXBLEController: disconnected, re-advertising");
    _state = 1;
    [_leds setBLEStatus:1];
    start_advertising();
}

- (void)forgetBondAndReadvertise
{
    OZLog("PXBLEController: forget bond + re-advertise");
    _unpairing = YES;
    unpair_all();
    _unpairing = NO;
    _state = 1;
    [_leds setBLEStatus:1];
    start_advertising();
}

@end
