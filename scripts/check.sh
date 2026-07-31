#!/bin/sh

echo "==========================CPU信息=========================="
echo "CPU物理数量: $(grep "physical id" /proc/cpuinfo | sort | uniq | wc -l)"
echo "CPU线程数量: $(nproc)"
echo "CPU型号信息: $(grep -m1 name /proc/cpuinfo | awk -F: '{print $2}')"
printf "\n"
echo "==========================内存信息=========================="
echo "已安装内存详细信息:"
sudo lshw -short -C memory 2>/dev/null | grep GiB
printf "\n"
echo "==========================硬盘信息=========================="
echo "硬盘数量: $(ls /dev/sd* 2>/dev/null | grep -v '[1-9]' | wc -l)"
echo "使用情况:"
df -hT
echo "=============================================================================="
