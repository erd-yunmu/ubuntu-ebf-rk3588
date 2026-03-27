# 概述
面向 Rockchip RK3588 系列（LubanCat-4/5/5-V2/5IO）的 Ubuntu 体验，提供预制服务器版与桌面版镜像，开机即用。

## 主要特性
- apt 包管理与系统更新（内核/固件/引导）
- 首次运行向导简化用户与桌面配置
- 硬件加速：panfork 3D、Mali OpenGL ES、Rockchip MPP 编解码
- 桌面：Wayland + GNOME，Chromium 流畅播放 4K YouTube；MPV/GStreamer 4K 播放
- 支持 Plex；内核 6.1.114

## 支持设备
- LubanCat-4
- LubanCat-5
- LubanCat-5-V2
- LubanCat-5IO

# 获取与校验
1. 从提供的下载源获取镜像（桌面/服务器版）。

# 安装

## SD 卡
1. 推荐使用 rufus（免安装、小体积）。若需其他版本可从 https://rufus.ie/zh/ 获取。
2. 打开 rufus，选择 SD 卡与镜像（可直接选择 .xz），开始写入，等待完成。

## eMMC 启动
1. 用 RKDevTool 进入 maskrom 模式。
2. 选择 “下载镜像”：`boot` 选 `rk3588_MiniLoaderAll.bin`；`system` 选解压后的 `.img`。
3. 勾选 “强制按地址写”，点击执行，等待完成。

## NVMe 启动
- 方案 A（先从 SD 引导到系统后写 NVMe）：
  ```bash
  xz -dc ubuntu-22.04.4-desktop-arm64-lubancat-5.img.xz | sudo dd of=/dev/nvme0n1 bs=4k
  sync
  ```
  断电拔卡后，按 MR 进入 maskrom，将 `rkspi_loader_lubancat_5.img` 刷入 eMMC 作为 NVMe 引导。
- 方案 B（从已启动系统直接写 NVMe，流程同上）。
- 停止 NVMe 启动（清除分区）：
  ```bash
  sudo dd if=/dev/zero of=/dev/nvme0n1 bs=8M count=1
  ```

# 登录信息
- 预设账户：用户 `cat` / 密码 `temppwd`
- 支持 HDMI 与串口登录。

# 编译

## 安装依赖
```bash
sudo apt-get install -y build-essential gcc-aarch64-linux-gnu bison \
qemu-user-static qemu-system-arm u-boot-tools binfmt-support \
debootstrap flex libssl-dev bc rsync kmod cpio xz-utils fakeroot parted \
udev dosfstools uuid-runtime git-lfs device-tree-compiler python3 fdisk \
python-is-python3
```

## 获取源码
```bash
git clone -b 24.04-panfrost https://github.com/erd-yunmu/ubuntu-ebf-rk3588
cd ubuntu-ebf-rk3588
git lfs fetch && git lfs checkout
```

## 构建镜像
```bash
sudo ./build.sh --board=lubancat-4        # 其他：lubancat-5 / lubancat-5-v2 / lubancat-5io
# 常用参数：-c 清理，-d Docker 构建，-k 仅内核，-u 仅 U-Boot，-so 仅服务器，-do 仅桌面，-v 详细日志
# 产物位于 images/
```

# 常见问题
- NVMe 启动失败：确认已刷入 `rkspi_loader_lubancat_5.img`；检查 NVMe 是否已写入镜像并 sync。
- GPG/仓库问题：如 apt 更新失败，检查网络与镜像源，必要时更换为官方/就近镜像。

---
Ubuntu is a trademark of Canonical Ltd. Rockchip is a trademark of Fuzhou Rockchip Electronics Co., Ltd. The Ubuntu Rockchip project is not affiliated with Canonical Ltd or Fuzhou Rockchip Electronics Co., Ltd. All other product names, logos, and brands are property of their respective owners. The Ubuntu name is owned by [Canonical Limited](https://ubuntu.com/).
