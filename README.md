# 概述
这个项目旨在为Rockchip RK3588 系列设备提供一个基于 Ubuntu 的操作系统体验。通过此项目，您可以：
立即启动：使用预制的 Ubuntu 服务器或桌面映像，快速获得一个熟悉的 Linux 环境，无需复杂的安装过程。
设备支持：目前支持的设备包括但不限于：
```bash
LubanCat-4
LubanCat-5
LubanCat-5-V2
LubanCat-5IO
```

# 特色功能

- **包管理**：利用官方Ubuntu存储库通过apt进行便捷的包管理，确保软件的更新和安全性。
- **系统更新**：通过apt轻松获取内核、固件和引导加载程序的最新更新，保持系统的稳定性和兼容性。
- **用户配置**：首次运行向导简化了桌面的用户设置和系统配置过程。
- **硬件加**速：通过panfork提供3D视频加速，提升图形性能。
- **图形支持**：基于Mali GPU的OpenGL ES支持，优化图形渲染效率。
- **桌面环境**：采用Wayland协议，全面支持GNOME桌面，提供流畅的用户体验。
- **视频播放**：Chromium浏览器支持高清4K YouTube视频流畅播放。
- **高清视频**：MPV视频播放器能够流畅播放4K视频内容。
- **多媒体处理**：Gstreamer作为命令行工具，支持4K视频的播放，为多媒体应用提供更多选择。
- **视频编码解码**：支持Rockchip MPP（Media Process Platform）进行高效的视频硬编码和硬解码。
- **预装软件**：已预装MPV，利用硬件解码能力提升视频播放性能。
- **容器化支持**：系统兼容Docker，方便用户部署和管理容器；也支持Plex服务器，满足多媒体服务器的需求。
- **内核版本**：采用稳定的6.1.84 Linux内核，确保系统的安全性和性能。

# 安装
### SD卡
* 1.使用工具烧录，三种rufus，win32diskimager,balenaEtcher选个工具，推荐 rufus，免安装，包又小
* rufus安装包在->网盘/6-开发软件/rufus-4.3.exe
* rufus如需安装其他版本，可从 https://rufus.ie/zh/ 下载
* 2.打开rufus，插上SD卡，点击“选择”镜像，可以不用解压，直接选上，点击开始烧录。等待写卡结束即可。

### EMMC启动
* 打开RKDevTool.exe工具，进入maskrom模式，
* 1.选择“下载镜像”下面有名字写着：boot  system
* 2.“boot”选择工具文件夹里面自带名是“rk3588_MiniLoaderAll.bin”点击右边“...”选择bin
* 3.“sysem”选择下载好的镜像，ubuntu**.xz压缩包，进行解压出镜像.img，点击右边“...”选择镜像.img
* 4.下方 打勾“强制按地址写”
* 5.最后点击“执行”正在刷入，等待结束。

### NVME启动
- 方法1：
```bash
镜像刷入SD卡上，按PWR键，上电自动进入SD加载镜像启动进系统
把 ubuntu-22.04.4-desktop-arm64-lubancat-5.img.xz 镜像包放到当前系统目录下，
执行xz -dc *-lubancat-5.img.xz | sudo dd of=/dev/nvme0n1 bs=4k 把镜像写入到NVME上，结束后执行sync，然后拔电，移除SD卡
再次按MR键进入maskrom模式，把 rkspi_loader_lubancat_5.img 刷入emmc作为引导nvme系统。刷完系统就自动引导起来了
 
cat@lubancat:~$ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           1.6G  2.7M  1.6G   1% /run
/dev/nvme0n1p2  7.9T  7.7G  4.4G   1% /
tmpfs           7.8G     0  7.8G   0% /dev/shm
tmpfs           5.0M  4.0K  5.0M   1% /run/lock
tmpfs           4.0M     0  4.0M   0% /sys/fs/cgroup
/dev/nvme0n1p1  511M   52M  460M  11% /boot/firmware
tmpfs           1.6G   80K  1.6G   1% /run/user/129
tmpfs           1.6G   68K  1.6G   1% /run/user/1000
cat@lubancat:~$
 
看到nvme就成功从nvme启动了。
 ```
- 方法2：
```bash
参考刷入emmc教程，然后启动进入系统
把 *-ubuntu-22.04.4-desktop-arm64-lubancat-5.img.xz 镜像包放到当前系统目录下，
执行xz -dc *-lubancat-5.img.xz | sudo dd of=/dev/nvme0n1 bs=4k 把镜像写入到NVME上，结束后执行sync，然后拔电
再次按MR键进入maskrom模式，把 rkspi_loader_lubancat_5.img 刷入emmc作为引导nvme系统。刷完系统就自动引导起来
 
破坏nvme分区，停止nvme启动系统，执行命令：dd if=/dev/zero of=/dev/nvme0n1 bs=8M count=1 之后拔电即可。
```

# 登录信息
* 对于桌面版和服务器映像，您将能够通过 HDMI 或串行控制台连接登录。预定义用户为`**cat**`，密码为`**temppwd**`。

# 编译
### 安装依赖
```
sudo apt-get install -y build-essential gcc-aarch64-linux-gnu bison \
qemu-user-static qemu-system-arm qemu-efi u-boot-tools binfmt-support \
debootstrap flex libssl-dev bc rsync kmod cpio xz-utils fakeroot parted \
udev dosfstools uuid-runtime git-lfs device-tree-compiler python3 fdisk bc \
python-is-python3
```

### 下载源码
```
git clone -b "分支" git@github.com:xxx/ubuntu-rockchip.git && cd ubuntu-rockchip
git lfs fetch && git lfs checkout
```

# 使用方法：
```
sudo ./build.sh --board=lubancat-4

# 支持的设备：
sudo ./build.sh --board=lubancat-4
sudo ./build.sh --board=lubancat-5      
sudo ./build.sh --board=lubancat-5-v2
sudo ./build.sh --board=lubancat-5io

# 参数说明：
  -b, --board=BOARD      目标板
  -h, --help             显示此帮助信息并退出
  -c, --clean            清理构建目录
  -d, --docker           使用Docker进行构建
  -k, --kernel-only      仅编译内核
  -u, --uboot-only       仅编译U-Boot
  -so, --server-only     仅构建服务镜像
  -do, --desktop-only    仅构建桌面镜像
  -l, --launchpad        使用Launchpad存储库的内核和U-Boot
  -v, --verbose          增加Bash脚本的详细程度

编译生成的镜像文件存放在 images 文件夹下。
```
# 单独编译内核
```bash
cd build/linux-rockchip
sudo -s # 切换为root用户进行编译
make CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 rockchip_linux_defconfig
make KBUILD_IMAGE="arch/arm64/boot/Image" CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 -j"$(nproc)" bindeb-pkg
# 生成的.deb包位于上级目录
```

镜像路径在images文件夹下

---
> Ubuntu is a trademark of Canonical Ltd. Rockchip is a trademark of Fuzhou Rockchip Electronics Co., Ltd. The Ubuntu Rockchip project is not affiliated with Canonical Ltd or Fuzhou Rockchip Electronics Co., Ltd. All other product names, logos, and brands are property of their respective owners. The Ubuntu name is owned by [Canonical Limited](https://ubuntu.com/).
