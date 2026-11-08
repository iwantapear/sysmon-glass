#!/bin/sh
# DGX Spark (GB10) 硬件状态探针 —— 输出 key=value 行
g=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
echo "gpu=$g"
echo "cpu=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)"
echo "fan=$(cat /sys/class/hwmon/hwmon0/fan1_input 2>/dev/null)"
for h in /sys/class/hwmon/hwmon*; do
  if [ "$(cat "$h/name" 2>/dev/null)" = "nvme" ]; then
    echo "nvme=$(cat "$h/temp1_input" 2>/dev/null)"
  fi
done
echo "mem=$(free -m | awk '/^Mem:/{print $3" "$2}')"
echo "load=$(awk '{print $1}' /proc/loadavg)"
echo "up=$(awk '{print int($1/3600)}' /proc/uptime)"
