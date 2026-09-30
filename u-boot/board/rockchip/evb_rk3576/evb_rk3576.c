/*
 * SPDX-License-Identifier:     GPL-2.0+
 *
 * (C) Copyright 2023 Rockchip Electronics Co., Ltd
 */

#include <common.h>
#include <boot_fit.h>
#include <dwc3-uboot.h>
#include <usb.h>
#include <linux/usb/phy-rockchip-usbdp.h>
#include <asm/io.h>
#include <rockusb.h>
#include <adc.h>
#include <dm.h>

#define SARADC_ADDR	"adc@2ae00000"
#define HW_ID_CHANNEL	2
#define BOM_ID_CHANNEL	5

#define countof(x) (sizeof(x) / sizeof(x[0]))

struct variant_def {
	char *compatible;
	unsigned int hw_id_lower_bound;
	unsigned int hw_id_upper_bound;
	unsigned int bom_id_lower_bound;
	unsigned int bom_id_upper_bound;
	char *fdtfile;
};

DECLARE_GLOBAL_DATA_PTR;

#ifdef CONFIG_USB_DWC3
#define CRU_BASE		0x27200000
#define CRU_SOFTRST_CON47	0x0abc
#define U3PHY_BASE		0x2b010000

static struct dwc3_device dwc3_device_data = {
	.maximum_speed = USB_SPEED_SUPER,
	.base = 0x23000000,
	.dr_mode = USB_DR_MODE_PERIPHERAL,
	.index = 0,
	.dis_u2_susphy_quirk = 1,
	.dis_u1u2_quirk = 1,
	.usb2_phyif_utmi_width = 16,
};

int usb_gadget_handle_interrupts(int index)
{
	dwc3_uboot_handle_interrupt(0);
	return 0;
}

bool rkusb_usb3_capable(void)
{
	return true;
}

static void usb_reset_otg_controller(void)
{
	writel(0x00200020, CRU_BASE + CRU_SOFTRST_CON47);
	mdelay(1);
	writel(0x00200000, CRU_BASE + CRU_SOFTRST_CON47);
	mdelay(1);
}

int board_usb_init(int index, enum usb_init_type init)
{
	u32 ret = 0;

	usb_reset_otg_controller();

#if defined(CONFIG_SUPPORT_USBPLUG)
	dwc3_device_data.maximum_speed = USB_SPEED_HIGH;

	if (rkusb_switch_usb3_enabled()) {
		dwc3_device_data.maximum_speed = USB_SPEED_SUPER;
		ret = rockchip_u3phy_uboot_init(U3PHY_BASE);
		if (ret) {
			rkusb_force_to_usb2(true);
			dwc3_device_data.maximum_speed = USB_SPEED_HIGH;
		}
	}
#else
	ret = rockchip_u3phy_uboot_init(U3PHY_BASE);
	if (ret) {
		rkusb_force_to_usb2(true);
		dwc3_device_data.maximum_speed = USB_SPEED_HIGH;
	}
#endif

	return dwc3_uboot_init(&dwc3_device_data);
}

#if defined(CONFIG_SUPPORT_USBPLUG)
int board_usb_cleanup(int index, enum usb_init_type init)
{
	dwc3_uboot_exit(index);
	return 0;
}
#endif

#endif

#ifdef CONFIG_ID_EEPROM
static struct variant_def variants[] = {
	{"radxa,cm4-io", 0, 40, 2000, 2080, "rockchip/rk3576-radxa-cm4-io.dtb"},
	{"radxa,cm4-rpi-cm4-io", 0, 40, 4045, 4095, "rockchip/rk3576-radxa-cm4-rpi-cm4-io.dtb"},
	{"radxa,rock-4d", 380, 460, 0, 40, "rockchip/rk3576-rock-4d.dtb"},
	{"radxa,rock-4d-spi", 380, 460, 2000, 2080, "rockchip/rk3576-rock-4d-spi.dtb"},
	{"radxa,nx4-c200", 780, 860, 0, -1, "rockchip/rk3576-radxa-nx4-c200.dtb"},
};

static void set_fdtfile(void)
{
	int i, ret;
	unsigned int hw_id, bom_id;
	struct variant_def *v;

	ret = adc_channel_single_shot(SARADC_ADDR, HW_ID_CHANNEL, &hw_id);
	if (ret) {
		pr_err("%s: adc_channel_single_shot fail for HW_ID: %i!\n", __func__, ret);
		return;
	}
	ret = adc_channel_single_shot(SARADC_ADDR, BOM_ID_CHANNEL, &bom_id);
	if (ret) {
		pr_err("%s: adc_channel_single_shot fail for BOM_ID: %i!\n", __func__, ret);
		return;
	}

	for(i = 0; i < countof(variants); i++) {
		v = &variants[i];
		if (hw_id >= v->hw_id_lower_bound &&
		    hw_id <= v->hw_id_upper_bound &&
		    bom_id >= v->bom_id_lower_bound &&
		    bom_id <= v->bom_id_upper_bound) {
			printf("Found matching variant %s for hw_id 0x%x and bom_id 0x%x setting fdtfile to %s\n", v->compatible, hw_id, bom_id, v->fdtfile);
			env_set("fdtfile", v->fdtfile);
			break;
		} else {
			printf("Checking variant: %s, hw_id 0x%x not in range [0x%x, 0x%x], bom_id 0x%x not in range [0x%x, 0x%x]\n",
			       v->compatible, hw_id, v->hw_id_lower_bound, v->hw_id_upper_bound, bom_id, v->bom_id_lower_bound, v->bom_id_upper_bound);
		}
	}
}

/**
 * mac_read_from_eeprom() - read the MAC address & the serial number in EEPROM
 *
 * This function reads the MAC address and the serial number from EEPROM and
 * sets the appropriate environment variables for each one read.
 *
 * The environment variables are only set if they haven't been set already.
 * This ensures that any user-saved variables are never overwritten.
 *
 * If CONFIG_ID_EEPROM is enabled, this function will be called in
 * "static init_fnc_t init_sequence_r[]" of u-boot/common/board_r.c.
 */
int mac_read_from_eeprom(void)
{
	set_fdtfile();
	return 0;
}

int do_mac(cmd_tbl_t *cmdtp, int flag, int argc, char * const argv[])
{
	printf("This device does not support user programmable EEPROM.\n");
	return -1;
}

#endif

#ifndef CONFIG_SPL_BUILD

#define LUBANCAT_ADC_CH_HIGH	2
#define LUBANCAT_ADC_CH_LOW	3
#define LUBANCAT_DTB_FIT_ADDR	0x41800000

static const unsigned int lubancat_adc_threshold[] = {
	916, 1376, 1840, 2380, 2928, 3432, 3900, 4096
};

struct lubancat_variant {
	unsigned int id;
	char *dtb;
};

static const struct lubancat_variant lubancat_variants[] = {
	{ 0, "rk3576-lubancat-3" },
	{ 1, "rk3576-lubancat-3io" },
};

static const char *lubancat_dtb_name = "";

static int lubancat_adc_read(unsigned int channel, unsigned int *value)
{
	int ret;

	ret = adc_channel_single_shot(SARADC_ADDR, channel, value);
	if (ret)
		ret = adc_channel_single_shot("saradc", channel, value);

	return ret;
}

static int lubancat_adc_index(unsigned int raw, unsigned int *index)
{
	unsigned int i;

	for (i = 0; i < countof(lubancat_adc_threshold); i++) {
		if (raw < lubancat_adc_threshold[i]) {
			*index = i;
			return 0;
		}
	}

	return -EINVAL;
}

static const char *lubancat_dtb_for_adc(void)
{
	unsigned int raw_high, raw_low, high, low, id;
	unsigned int i;

	if (lubancat_adc_read(LUBANCAT_ADC_CH_HIGH, &raw_high) ||
	    lubancat_adc_read(LUBANCAT_ADC_CH_LOW, &raw_low))
		return NULL;

	if (lubancat_adc_index(raw_high, &high) || lubancat_adc_index(raw_low, &low))
		return NULL;

	id = high * 100 + low;

	for (i = 0; i < countof(lubancat_variants); i++) {
		if (lubancat_variants[i].id == id) {
			printf("lubancat: ch2=%u ch3=%u id=%03u -> dtb %s\n",
			       raw_high, raw_low, id, lubancat_variants[i].dtb);
			return lubancat_variants[i].dtb;
		}
	}

	printf("lubancat: ch2=%u ch3=%u id=%03u not matched\n", raw_high, raw_low, id);

	return NULL;
}

int board_fit_config_name_match(const char *name)
{
	const char *base;
	size_t len;

	if (!lubancat_dtb_name || !lubancat_dtb_name[0])
		return -1;

	base = strrchr(name, '/');
	base = base ? base + 1 : name;
	len = strlen(lubancat_dtb_name);

	if (strncmp(base, lubancat_dtb_name, len))
		return -1;

	if (base[len] && base[len] != '.')
		return -1;

	return 0;
}

int embedded_dtb_select(void)
{
	void *blob;

	lubancat_dtb_name = lubancat_dtb_for_adc();
	if (!lubancat_dtb_name)
		return 0;

	blob = locate_dtb_in_fit((void *)LUBANCAT_DTB_FIT_ADDR);
	if (!blob) {
		printf("lubancat: no dtb in fit\n");
		return 0;
	}

	gd->fdt_blob = blob;

	return fdtdec_prepare_fdt();
}

#endif
