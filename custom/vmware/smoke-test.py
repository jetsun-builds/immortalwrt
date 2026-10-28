#!/usr/bin/env python3
"""Boot disposable VMDK snapshots with EFI, VMware SCSI, and two NIC models."""
from pathlib import Path
import json
import shutil
import sys

import pexpect

out = Path(sys.argv[1]).resolve()
image = next(out.glob('*-squashfs-combined-efi.vmdk'))
requested = Path(__file__).with_name('packages.txt').read_text().split()
installed = {line.split(' - ')[0] for line in (out / 'packages.manifest').read_text().splitlines()}
missing = sorted(set(requested) - installed)
if missing:
    raise SystemExit(f'Requested packages missing from image: {missing}')

code = Path('/usr/share/OVMF/OVMF_CODE_4M.fd')
vars_template = Path('/usr/share/OVMF/OVMF_VARS_4M.fd')
assert code.is_file() and vars_template.is_file(), 'OVMF firmware missing'
results = []
for nic in ('e1000', 'vmxnet3'):
    variables = out / f'ovmf-{nic}.fd'
    shutil.copyfile(vars_template, variables)
    args = [
        '-machine', 'q35', '-accel', 'tcg', '-m', '1024', '-smp', '2',
        '-drive', f'if=pflash,format=raw,readonly=on,file={code}',
        '-drive', f'if=pflash,format=raw,file={variables}',
        '-device', 'pvscsi,id=scsi',
        '-drive', f'if=none,id=disk,format=vmdk,file={image},snapshot=on',
        '-device', 'scsi-hd,drive=disk,bus=scsi.0,bootindex=1',
        '-netdev', 'user,id=wan,net=10.0.2.0/24',
        '-device', f'{nic},netdev=wan,mac=52:54:00:12:34:00',
        '-netdev', 'user,id=lan,net=192.0.2.0/24,restrict=on',
        '-device', f'{nic},netdev=lan,mac=52:54:00:12:34:01',
        '-display', 'none', '-serial', 'stdio', '-monitor', 'none', '-no-reboot',
    ]
    with (out / f'boot-{nic}.log').open('w') as log:
        child = pexpect.spawn('qemu-system-x86_64', args, encoding='utf-8', codec_errors='replace', timeout=300)
        child.logfile = log
        try:
            child.expect('Please press Enter to activate this console')
            child.sendline('')
            child.expect(r'root@[^\r\n]*[~/#] ')
            child.sendline('stty -echo')
            child.expect(r'root@[^\r\n]*[~/#] ')
            checks = [
                'test -d /sys/firmware/efi',
                'test "$(uci get network.wan.device)" = eth0',
                'test "$(uci get network.wan.proto)" = dhcp',
                'test "$(uci get network.lan.device)" = br-lan',
                'test "$(uci get network.lan_bridge.ports)" = eth1',
                'test "$(uci get network.lan.ipaddr)" = 192.168.3.1',
                'test -d /sys/class/net/br-lan/brif/eth1',
                'test ! -e /sys/class/net/br-lan/brif/eth0',
                'ip -4 addr show dev br-lan | grep -q 192.168.3.1/24',
                'test "$(uci get dhcp.lan.ignore)" = 0',
                'pidof dnsmasq',
                'test -c /dev/net/tun',
                'nft list table inet fw4',
                'grep -q " /rom squashfs " /proc/mounts',
                'for tool in tmux htop btop nano cpupower vnstat vnstati nlbwmon; do command -v "$tool" || exit 1; done',
                'for n in $(seq 1 60); do [ "$(ubus call network.interface.wan status | jsonfilter -e @.up)" = true ] && break; sleep 2; done',
                'test "$(ubus call network.interface.wan status | jsonfilter -e @.up)" = true',
            ]
            command = '( sleep 15; ' + ' && '.join(checks) + " ) && printf 'VMWARE_%s\\n' PASS || printf 'VMWARE_%s\\n' FAIL"
            child.sendline(command)
            index = child.expect(['VMWARE_PASS', 'VMWARE_FAIL', pexpect.EOF, pexpect.TIMEOUT], timeout=240)
            if index != 0:
                raise RuntimeError(f'{nic}: boot or network validation failed; see boot-{nic}.log')
            results.append({'nic': nic, 'firmware': 'UEFI', 'disk_controller': 'VMware PVSCSI', 'result': 'passed'})
            print(f'{nic}: UEFI, VMware SCSI, WAN DHCP, LAN bridge, firewall, TUN and tools passed', flush=True)
        finally:
            child.close(force=True)
            variables.unlink(missing_ok=True)

(out / 'validation.json').write_text(json.dumps({'packages_checked': len(requested), 'boots': results}, indent=2) + '\n')
