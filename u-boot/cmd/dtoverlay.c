// SPDX-License-Identifier: GPL-2.0+
/*
 * Apply the device tree overlays listed in a configuration file.
 *
 * The configuration file holds one entry per line:
 *
 *	dtoverlay=/dtb/overlay/<name>.dtbo
 *
 * Lines commented out with '#' are skipped, so an overlay is enabled or
 * disabled by (un)commenting its line.
 */

#include <common.h>
#include <command.h>
#include <fs.h>
#include <fdt_support.h>
#include <mapmem.h>

extern struct fdt_header *working_fdt;

#define DTOVERLAY_KEY		"dtoverlay="
#define DTOVERLAY_KEY_LEN	(sizeof(DTOVERLAY_KEY) - 1)
#define DTOVERLAY_PATH_LEN	256

static int dtoverlay_apply(const char *ifname, const char *dev_part,
			   const char *path)
{
	ulong addr = env_get_ulong("fdtoverlay_addr_r", 16, 0);
	loff_t actread = 0;
	void *blob;
	int ret;

	if (!addr) {
		printf("dtoverlay: fdtoverlay_addr_r is not set\n");
		return -1;
	}

	if (fs_set_blk_dev(ifname, dev_part, FS_TYPE_ANY)) {
		printf("dtoverlay: no filesystem on %s %s\n", ifname, dev_part);
		return -1;
	}

	/* len == 0 reads the whole file, fs_close() drops the fs type again */
	if (fs_read(path, addr, 0, 0, &actread)) {
		printf("dtoverlay: cannot read %s\n", path);
		return -1;
	}

	blob = map_sysmem(addr, actread);
	printf("Applying device tree overlay: %s\n", path);
	ret = fdt_overlay_apply_verbose(working_fdt, blob);
	unmap_sysmem(blob);

	return ret;
}

static int do_dtoverlay(cmd_tbl_t *cmdtp, int flag, int argc,
			char * const argv[])
{
	const char *ifname, *dev_part, *buf, *p, *end;
	ulong addr, size;
	int applied = 0, failed = 0;

	if (argc != 5)
		return CMD_RET_USAGE;

	addr = simple_strtoul(argv[1], NULL, 16);
	size = simple_strtoul(argv[2], NULL, 16);
	ifname = argv[3];
	dev_part = argv[4];

	if (!working_fdt) {
		printf("dtoverlay: no working fdt, run 'fdt addr' first\n");
		return CMD_RET_FAILURE;
	}

	buf = map_sysmem(addr, size);
	end = buf + size;

	p = buf;
	while (p < end) {
		const char *nl = memchr(p, '\n', end - p);
		const char *line_end = nl ? nl : end;
		const char *value = p, *value_end;
		char path[DTOVERLAY_PATH_LEN];
		int len;

		while (value < line_end && (*value == ' ' || *value == '\t'))
			value++;

		if (value < line_end && *value != '#' &&
		    (size_t)(line_end - value) >= DTOVERLAY_KEY_LEN &&
		    !memcmp(value, DTOVERLAY_KEY, DTOVERLAY_KEY_LEN)) {
			value += DTOVERLAY_KEY_LEN;
			while (value < line_end && (*value == ' ' ||
						    *value == '\t'))
				value++;

			value_end = line_end;
			while (value_end > value &&
			       (value_end[-1] == '\r' || value_end[-1] == ' ' ||
				value_end[-1] == '\t'))
				value_end--;

			len = value_end - value;
			if (len > 0) {
				if (len > DTOVERLAY_PATH_LEN - 1)
					len = DTOVERLAY_PATH_LEN - 1;
				memcpy(path, value, len);
				path[len] = '\0';

				if (dtoverlay_apply(ifname, dev_part, path))
					failed++;
				else
					applied++;
			}
		}

		if (!nl)
			break;
		p = nl + 1;
	}

	unmap_sysmem((void *)buf);

	printf("dtoverlay: %d applied, %d failed\n", applied, failed);

	return failed ? CMD_RET_FAILURE : CMD_RET_SUCCESS;
}

U_BOOT_CMD(
	dtoverlay, 5, 0, do_dtoverlay,
	"apply the device tree overlays listed in a config file",
	"<addr> <size> <interface> <dev[:part]>\n"
	"    - apply every uncommented 'dtoverlay=' line of the config file\n"
	"      loaded at <addr>, reading the overlay files from <dev>"
);
