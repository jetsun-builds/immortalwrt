# ImmortalWrt 25.12.2 for VMware Workstation

使用官方 25.12.2 x86/64 ImageBuilder 生成定制 squashfs EFI VMDK，复用官方内核和软件包。
根分区 1024 MiB，含可写 overlay；不是把现有 332 MB 虚拟磁盘直接覆盖升级。

## 网络默认值

| VMware 连接 | 虚拟机接口 | 用途 |
| --- | --- | --- |
| 第一张虚拟网卡 → VMnet2 | eth0 | WAN，DHCP；WAN6，DHCPv6 |
| 第二张虚拟网卡 → VMnet3 | eth1 → br-lan | LAN，192.168.3.1/24 |

LAN DHCP 地址池为 192.168.3.100–249，租期 12 小时。中文 LuCI 地址：http://192.168.3.1/ 。
系统时区为 Asia/Shanghai。标准 firewall4/nftables 提供 LAN → WAN 转发和 NAT，WAN 不开放管理服务。
网卡实际编号请在首次启动时对照 VMware 的 MAC 地址确认；PCI 插槽顺序可能改变 eth0/eth1 顺序。

## 内置软件

- vnStat Graphs（vnstat2、vnstati2、中文 LuCI）
- Netlink Bandwidth Monitor（nlbwmon、中文 LuCI）
- LuCI Statistics、CPU/频率/接口/负载/内存/磁盘统计
- tmux、htop、btop、nano、cpupower
- DDNS、常见服务定义、中文 LuCI；域名和凭据需自行设置
- UPnP（miniupnpd-nftables、中文 LuCI）；启用和映射策略可在 LuCI 中调整
- nftables-json、TUN、nft TPROXY/socket 支持
- E1000、E1000e、VMXNET3 驱动；VMware PVSCSI 支持来自官方内核

官方仓库未提供独立 luci-app-cpufreq，使用 cpupower 和 collectd-mod-cpufreq。
VMware 通常不向客户机提供物理 CPU 调频功能；相关界面可能没有数据。
当前使用官方 nlbwmon，没有自动合并其他分支中的 nlbwmon 自定义补丁。

## 导入 VMware

1. 关闭虚拟机并备份原虚拟磁盘及配置。解压 Actions 的 artifact ZIP。
2. 将解压后的 `immortalwrt-25.12.2-x86-64-generic-squashfs-combined-efi.vmdk` 放在虚拟机目录。
3. 使用已有虚拟磁盘，把此 VMDK 设为启动磁盘。建议使用 SATA（本次自动启动测试的磁盘控制器）。
4. 固件选择 UEFI，关闭 Secure Boot；内存 2 GB、CPU 2 核即可。
5. 第一张网卡选 VMnet2，第二张选 VMnet3，两张均勾选开机连接。可用 E1000e 或 VMXNET3。
6. 确保宿主机的 VMnet2/VMnet3 分别桥接到预期的 USB 网卡；两侧网络应分离。
7. 从 LAN 侧访问 http://192.168.3.1/，用户名 root，首次登录后设置密码。

上游 WAN 网络不要使用 192.168.3.0/24，否则需调整一侧网段。
USB 网卡由宿主机管理并桥接，不需要把 USB 设备直通给虚拟机。

## 构建与验证

Actions 工作流：`.github/workflows/vmware-x86-64.yml`。
打开或更新本 PR 自动构建；合并后也可以在 Actions 使用 Run workflow。
`custom/vmware/packages.txt` 保存显式包清单，`network` 保存出厂网络配置。

构建固定 ImageBuilder SHA256，并使用官方签名软件仓库。
工作流核对全部显式包，再用 QEMU/OVMF 和 SATA 启动磁盘的临时快照，分别测试 E1000、VMXNET3 双网卡。
检查 EFI、squashfs、eth0 的 WAN DHCP、eth1 的 br-lan、192.168.3.1/24、DHCP 服务、nftables、TUN 和终端工具。
自动测试不能替代在实际 VMware 和 USB 桥接环境中的测试。

产物包含 VMDK、SHA256SUMS、完整包清单、构建日志和启动验证日志；Actions artifact 保留 30 天。
仅在工作流成功、validation.json 显示两项 passed 时使用该次产物；失败运行也上传日志供诊断。
