# Target platforms supported by u-boot.
# debian/rules includes this Makefile snippet.

u-boot-rockchip_platforms += lubancat-3-rk3576
lubancat-3-rk3576_ddr := rk3576_ddr_lp4_1848MHz_lp5_2736MHz_v1.09.bin
lubancat-3-rk3576_bl31 := rk3576_bl31_v1.22.elf
lubancat-3-rk3576_bl32 := rk3576_bl32_v1.07.bin
lubancat-3-rk3576_pkg := lubancat-3

u-boot-rockchip_platforms += lubancat-3io-rk3576
lubancat-3io-rk3576_ddr := rk3576_ddr_lp4_1848MHz_lp5_2736MHz_v1.09.bin
lubancat-3io-rk3576_bl31 := rk3576_bl31_v1.22.elf
lubancat-3io-rk3576_bl32 := rk3576_bl32_v1.07.bin
lubancat-3io-rk3576_pkg := lubancat-3io