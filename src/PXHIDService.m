/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXHIDService.m
 * @brief BLE HID keyboard GATT service definition, read/write callbacks,
 *        and key-to-HID report building — all in one translation unit.
 */
#import "PXHIDService.h"

#include <zephyr/types.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#include <zephyr/sys/printk.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>

/* ---- HID descriptors ---- */

#define HIDS_REMOTE_WAKE          BIT(0)
#define HIDS_NORMALLY_CONNECTABLE BIT(1)

struct hids_info {
        uint16_t version;
        uint8_t code;
        uint8_t flags;
} __packed;

struct hids_report {
        uint8_t id;
        uint8_t type;
} __packed;

#define HIDS_INPUT  0x01
#define HIDS_OUTPUT 0x02

static struct hids_info sInfo = {
        .version = 0x0111, /* HID 1.11 */
        .code = 0x00,      /* No country code */
        .flags = HIDS_NORMALLY_CONNECTABLE,
};

static struct hids_report sInputRef = {
        .id = 0x01,
        .type = HIDS_INPUT,
};

static uint8_t sNotificationsEnabled;
static uint8_t sCtrlPoint;

/* Standard keyboard report map */
static uint8_t sReportMap[] = {
        0x05, 0x01, /* Usage Page (Generic Desktop) */
        0x09, 0x06, /* Usage (Keyboard) */
        0xA1, 0x01, /* Collection (Application) */
        0x85, 0x01, /*   Report Id (1) */
        /* Modifier keys (8 bits) */
        0x05, 0x07, /*   Usage Page (Keyboard/Keypad) */
        0x19, 0xE0, /*   Usage Min (Left Control) */
        0x29, 0xE7, /*   Usage Max (Right GUI) */
        0x15, 0x00, /*   Logical Min (0) */
        0x25, 0x01, /*   Logical Max (1) */
        0x75, 0x01, /*   Report Size (1) */
        0x95, 0x08, /*   Report Count (8) */
        0x81, 0x02, /*   Input (Data, Var, Abs) */
        /* Reserved byte */
        0x75, 0x08, /*   Report Size (8) */
        0x95, 0x01, /*   Report Count (1) */
        0x81, 0x01, /*   Input (Const) */
        /* Key array (6 keys) */
        0x05, 0x07, /*   Usage Page (Keyboard/Keypad) */
        0x19, 0x00, /*   Usage Min (0) */
        0x29, 0x65, /*   Usage Max (101) */
        0x15, 0x00, /*   Logical Min (0) */
        0x25, 0x65, /*   Logical Max (101) */
        0x75, 0x08, /*   Report Size (8) */
        0x95, 0x06, /*   Report Count (6) */
        0x81, 0x00, /*   Input (Data, Array) */
        0xC0,       /* End Collection */
};

/* ---- GATT read/write callbacks ---- */

static ssize_t read_info(struct bt_conn *conn,
                         const struct bt_gatt_attr *attr, void *buf,
                         uint16_t len, uint16_t offset)
{
        return bt_gatt_attr_read(conn, attr, buf, len, offset,
                                 attr->user_data, sizeof(struct hids_info));
}

static ssize_t read_report_map(struct bt_conn *conn,
                               const struct bt_gatt_attr *attr, void *buf,
                               uint16_t len, uint16_t offset)
{
        return bt_gatt_attr_read(conn, attr, buf, len, offset,
                                 sReportMap, sizeof(sReportMap));
}

static ssize_t read_report(struct bt_conn *conn,
                           const struct bt_gatt_attr *attr, void *buf,
                           uint16_t len, uint16_t offset)
{
        return bt_gatt_attr_read(conn, attr, buf, len, offset,
                                 attr->user_data, sizeof(struct hids_report));
}

static void input_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
        sNotificationsEnabled = (value == BT_GATT_CCC_NOTIFY) ? 1 : 0;
        printk("HID input notifications %s\n",
               sNotificationsEnabled ? "enabled" : "disabled");
}

static ssize_t read_input_report(struct bt_conn *conn,
                                 const struct bt_gatt_attr *attr, void *buf,
                                 uint16_t len, uint16_t offset)
{
        return bt_gatt_attr_read(conn, attr, buf, len, offset, NULL, 0);
}

static ssize_t write_ctrl_point(struct bt_conn *conn,
                                const struct bt_gatt_attr *attr,
                                const void *buf, uint16_t len,
                                uint16_t offset, uint8_t flags)
{
        uint8_t *value = attr->user_data;

        if (offset + len > sizeof(sCtrlPoint)) {
                return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
        }

        memcpy(value + offset, buf, len);
        return len;
}

/* Require encryption */
#define HID_PERM_READ  BT_GATT_PERM_READ_ENCRYPT
#define HID_PERM_WRITE BT_GATT_PERM_WRITE_ENCRYPT

/* HID Service Declaration */
BT_GATT_SERVICE_DEFINE(hid_kbd_svc,
        BT_GATT_PRIMARY_SERVICE(BT_UUID_HIDS),
        BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_INFO, BT_GATT_CHRC_READ,
                               BT_GATT_PERM_READ, read_info, NULL, &sInfo),
        BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_REPORT_MAP, BT_GATT_CHRC_READ,
                               BT_GATT_PERM_READ, read_report_map, NULL, NULL),
        BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_REPORT,
                               BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
                               HID_PERM_READ,
                               read_input_report, NULL, NULL),
        BT_GATT_CCC(input_ccc_changed,
                     HID_PERM_READ | HID_PERM_WRITE),
        BT_GATT_DESCRIPTOR(BT_UUID_HIDS_REPORT_REF, BT_GATT_PERM_READ,
                           read_report, NULL, &sInputRef),
        BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_CTRL_POINT,
                               BT_GATT_CHRC_WRITE_WITHOUT_RESP,
                               BT_GATT_PERM_WRITE,
                               NULL, write_ctrl_point, &sCtrlPoint),
);

/* ---- Key mapping: sw0->P, sw1->X, sw2->K, sw3->B ---- */

static const uint8_t sKeyMap[4] = { 0x13, 0x1B, 0x0E, 0x05 };

/* ---- PXHIDService ---- */

static PXHIDService *sSharedService;

@implementation PXHIDService

+ (void)initialize
{
    sSharedService = [[PXHIDService alloc] init];
}

+ (PXHIDService *)shared
{
    return sSharedService;
}

- (id)init
{
    self = [super init];
    if (self) {
        OZLog("PXHIDService: initialized");
    }
    return self;
}

- (void)sendReportForMask:(uint8_t)mask
{
    if (!sNotificationsEnabled) {
        return;
    }

    uint8_t keys[6] = {0};
    int idx = 0;

    for (int i = 0; i < 4 && idx < 6; i++) {
        if (mask & (1 << i)) {
            keys[idx++] = sKeyMap[i];
        }
    }

    uint8_t report[8];

    report[0] = 0; /* no modifiers */
    report[1] = 0; /* reserved */
    memcpy(&report[2], keys, 6);

    bt_gatt_notify(NULL, &hid_kbd_svc.attrs[5], report, sizeof(report));
}

- (BOOL)isSubscribed
{
    return sNotificationsEnabled ? YES : NO;
}

@end
