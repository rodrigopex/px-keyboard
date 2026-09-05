/*
 * Copyright (c) 2025 Rodrigo Peixoto <rodrigopex@gmail.com>
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * @file PXHIDService.m
 * @brief HID GATT service, report map, and chan_keys -> report.
 */
#import "PXHIDService.h"
#import "PXKeyboard.h"

#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/sys/printk.h>
#include <zephyr/types.h>
#include <zephyr/usb/class/hid.h>

/* ---- HID descriptors ---- */

#define HIDS_REMOTE_WAKE          BIT(0)
#define HIDS_NORMALLY_CONNECTABLE BIT(1)

#define HIDS_INPUT  0x01
#define HIDS_OUTPUT 0x02

/** @brief Keys carried in one boot-protocol report. */
#define PX_REPORT_KEYS 6

/** @brief Report layout: modifiers, reserved, then the key array. */
#define PX_REPORT_LEN (2 + PX_REPORT_KEYS)

struct hids_info {
	uint16_t version;
	uint8_t code;
	uint8_t flags;
} __packed;

struct hids_report {
	uint8_t id;
	uint8_t type;
} __packed;

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

/*
 * Standard boot-protocol keyboard report map, written with Zephyr's own HID
 * item macros (zephyr/usb/class/hid.h) rather than raw hex, so each line
 * says what it means.
 */
static uint8_t sReportMap[] = {
	HID_USAGE_PAGE(HID_USAGE_GEN_DESKTOP),
	HID_USAGE(HID_USAGE_GEN_DESKTOP_KEYBOARD),
	HID_COLLECTION(HID_COLLECTION_APPLICATION),
		HID_REPORT_ID(0x01),
		/* Modifier keys — one bit each */
		HID_USAGE_PAGE(HID_USAGE_GEN_KEYBOARD),
		HID_USAGE_MIN8(0xE0), /* Left Control  */
		HID_USAGE_MAX8(0xE7), /* Right GUI     */
		HID_LOGICAL_MIN8(0),
		HID_LOGICAL_MAX8(1),
		HID_REPORT_SIZE(1),
		HID_REPORT_COUNT(8),
		HID_INPUT(0x02), /* Data, Var, Abs */
		/* Reserved byte */
		HID_REPORT_SIZE(8),
		HID_REPORT_COUNT(1),
		HID_INPUT(0x01), /* Const */
		/* Key array */
		HID_USAGE_PAGE(HID_USAGE_GEN_KEYBOARD),
		HID_USAGE_MIN8(0),
		HID_USAGE_MAX8(101),
		HID_LOGICAL_MIN8(0),
		HID_LOGICAL_MAX8(101),
		HID_REPORT_SIZE(8),
		HID_REPORT_COUNT(PX_REPORT_KEYS),
		HID_INPUT(0x00), /* Data, Array */
	HID_END_COLLECTION,
};

/* ---- GATT read/write callbacks ---- */

static ssize_t read_info(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf,
			 uint16_t len, uint16_t offset)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset, attr->user_data,
				 sizeof(struct hids_info));
}

static ssize_t read_report_map(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf,
			       uint16_t len, uint16_t offset)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset, sReportMap, sizeof(sReportMap));
}

static ssize_t read_report(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf,
			   uint16_t len, uint16_t offset)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset, attr->user_data,
				 sizeof(struct hids_report));
}

static void input_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
	sNotificationsEnabled = (value == BT_GATT_CCC_NOTIFY) ? 1 : 0;
	printk("HID input notifications %s\n", sNotificationsEnabled ? "enabled" : "disabled");
}

static ssize_t read_input_report(struct bt_conn *conn, const struct bt_gatt_attr *attr, void *buf,
				 uint16_t len, uint16_t offset)
{
	return bt_gatt_attr_read(conn, attr, buf, len, offset, NULL, 0);
}

static ssize_t write_ctrl_point(struct bt_conn *conn, const struct bt_gatt_attr *attr,
				const void *buf, uint16_t len, uint16_t offset, uint8_t flags)
{
	uint8_t *value = attr->user_data;

	if (offset + len > sizeof(sCtrlPoint)) {
		return BT_GATT_ERR(BT_ATT_ERR_INVALID_OFFSET);
	}

	memcpy(value + offset, buf, len);
	return len;
}

/* Reports carry keystrokes, so require encryption. */
#define HID_PERM_READ  BT_GATT_PERM_READ_ENCRYPT
#define HID_PERM_WRITE BT_GATT_PERM_WRITE_ENCRYPT

BT_GATT_SERVICE_DEFINE(hid_kbd_svc,
	BT_GATT_PRIMARY_SERVICE(BT_UUID_HIDS),
	BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_INFO, BT_GATT_CHRC_READ, BT_GATT_PERM_READ,
			       read_info, NULL, &sInfo),
	BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_REPORT_MAP, BT_GATT_CHRC_READ, BT_GATT_PERM_READ,
			       read_report_map, NULL, NULL),
	BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_REPORT, BT_GATT_CHRC_READ | BT_GATT_CHRC_NOTIFY,
			       HID_PERM_READ, read_input_report, NULL, NULL),
	BT_GATT_CCC(input_ccc_changed, HID_PERM_READ | HID_PERM_WRITE),
	BT_GATT_DESCRIPTOR(BT_UUID_HIDS_REPORT_REF, BT_GATT_PERM_READ, read_report, NULL,
			   &sInputRef),
	BT_GATT_CHARACTERISTIC(BT_UUID_HIDS_CTRL_POINT, BT_GATT_CHRC_WRITE_WITHOUT_RESP,
			       BT_GATT_PERM_WRITE, NULL, write_ctrl_point, &sCtrlPoint),
);

/*
 * The input-report characteristic declaration, which bt_gatt_notify resolves
 * to the value handle itself. Each BT_GATT_CHARACTERISTIC above contributes
 * two attributes, so this is the third characteristic's declaration --
 * the same index Zephyr's own HOG sample uses. Asserted at init, so
 * reordering the table above fails loudly rather than notifying the wrong
 * handle.
 */
#define PX_HID_REPORT_ATTR 5

/*
 * Async rather than a plain listener: bt_gatt_notify allocates from the ATT
 * pool, and this keeps that off the input-subsystem callback's thread. The
 * async listener's FIFO preserves order, which HID reports need.
 */
OZM(ZBUS_ASYNC_LISTENER_DEFINE, alis_hid_report,
    ^(const struct zbus_channel *chan, const void *message) {
	const struct msg_keys *keys = message;
	[[PXHIDService sharedInstance] sendReportForMask:keys->mask];
});

ZBUS_OBS_DECLARE(alis_hid_report)

ZBUS_CHAN_ADD_OBS(chan_keys, alis_hid_report, 2);

/* ---- Key mapping: sw0->P, sw1->X, sw2->K, sw3->B, spelling PX-KB ---- */

static const uint8_t sKeyMap[PX_KEY_COUNT] = {
	[PX_KEY_P] = HID_KEY_P,
	[PX_KEY_X] = HID_KEY_X,
	[PX_KEY_K] = HID_KEY_K,
	[PX_KEY_B] = HID_KEY_B,
};

static PXHIDService *sSharedService;

@implementation PXHIDService

+ (void)initialize
{
	sSharedService = [[PXHIDService alloc] init];
}

+ (instancetype)sharedInstance
{
	return sSharedService;
}

- (id)init
{
	self = [super init];
	if (self) {
		oz_assert(!bt_uuid_cmp(hid_kbd_svc.attrs[PX_HID_REPORT_ATTR].uuid,
				       BT_UUID_GATT_CHRC));
		OZLog("PXHIDService: initialized");
	}
	return self;
}

- (void)sendReportForMask:(uint8_t)mask
{
	if (!sNotificationsEnabled) {
		return;
	}

	uint8_t report[PX_REPORT_LEN] = {0};
	int idx = 2; /* report[0] modifiers, report[1] reserved */

	for (int key = 0; key < PX_KEY_COUNT && idx < PX_REPORT_LEN; key++) {
		if (mask & BIT(key)) {
			report[idx] = sKeyMap[key];
			idx++;
		}
	}

	int ret = bt_gatt_notify(NULL, &hid_kbd_svc.attrs[PX_HID_REPORT_ATTR], report,
				 sizeof(report));
	if (ret < 0 && ret != -ENOTCONN) {
		OZLog("PXHIDService: notify failed: %d", ret);
	}
}

- (BOOL)isSubscribed
{
	return sNotificationsEnabled ? YES : NO;
}

- (int)cDescription:(char *)buf maxLength:(size_t)maxLen
{
	return snprintk(buf, maxLen, "<PXHIDService: subscribed=%d, report_map=%u bytes>",
			sNotificationsEnabled, (unsigned int)sizeof(sReportMap));
}

@end
