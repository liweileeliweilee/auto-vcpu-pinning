#!/bin/bash

echo "📂 建立 auto-vcpu-pinning.sh..."
sudo tee /usr/local/bin/auto-vcpu-pinning.sh > /dev/null << 'EOF'
#!/bin/bash
# auto-vcpu-pinning.sh
#
# 功能：
# 1. 無參數時，列出所有 VM 的 vCPU 配置（cores, sockets, cpu, numa）。
# 2. 根據輸入參數，固定分配指定 VM 的 CPU 核心。
#    輸入格式：VMID:cpu1,cpu2,...
#    例如：./auto-vcpu-pinning.sh 812:14,15 820:10,11,12,13
# 3. 支援 --reset VMID，用於恢復該 VM 的 CPU pinning（保留 cores 原設定）。
# 4. 支援 --reset all，恢復所有 VM 的 CPU pinning（保留 cores 原設定）。
# 5. 自動計算 cores 數量，並用 --numa0 cpus= 指定 CPU 核心（用分號分隔）。
# 6. 其他未指定的 VM 保持現有設定，不做修改，只顯示跳過提示。
#
# 使用環境：
# - 需在 Proxmox VE 主機上以 root 或 sudo 權限執行。
# - 使用 qm 命令管理虛擬機。
#
# 注意事項：
# - CPU 核心 ID 請自行確認對應正確。
# - numa0 設定會覆蓋 NUMA 配置，請確保此操作對虛擬機運行無負面影響。
# - CPU 核心 ID 間用逗號分隔，內部會轉成分號以符合 qm 指令格式。

if [ $# -eq 0 ]; then
  echo "=== 列出所有 VM 的 vCPU 配置 ==="
  for vmid in $(sudo qm list | awk 'NR>1 {print $1}'); do
    echo "VM $vmid:"
    sudo qm config "$vmid" | grep -E '^(cores|sockets|cpu|numa)' | sed 's/^/  /'
  done
  echo ""
  echo "用法：$0 VMID:cpu1,cpu2,... [VMID:cpu1,cpu2,...]"
  echo "      $0 --reset VMID [--reset VMID ...]"
  echo "      $0 --reset all"
  echo "例如：$0 812:14,15 820:10,11,12,13"
  echo "      $0 --reset 812"
  echo "      $0 --reset all"
  exit 0
fi

declare -A FIXED_PINNING
declare -a RESET_VMS=()
RESET_ALL=0

# 解析參數
while [ $# -gt 0 ]; do
  case "$1" in
    --reset)
      shift
      if [[ "$1" == "all" ]]; then
        RESET_ALL=1
        shift
      elif [[ "$1" =~ ^[0-9]+$ ]]; then
        RESET_VMS+=("$1")
        shift
      else
        echo "錯誤：--reset 後面需接 VMID（數字）或 all，輸入錯誤：$1"
        exit 1
      fi
      ;;
    *)
      vmid="${1%%:*}"
      cpus="${1#*:}"
      if [[ ! "$vmid" =~ ^[0-9]+$ ]]; then
        echo "錯誤：VMID 必須是數字，輸入錯誤：$vmid"
        exit 1
      fi
      if [[ "$cpus" =~ [^0-9,] ]]; then
        echo "錯誤：CPU 清單只能包含數字與逗號，輸入錯誤：$cpus"
        exit 1
      fi
      FIXED_PINNING[$vmid]=$cpus
      shift
      ;;
  esac
done

ALL_VMS=($(sudo qm list | awk 'NR>1 {print $1}'))

if [[ $RESET_ALL -eq 1 ]]; then
  echo "開始恢復所有 VM 的 pinning 設定（保留原 cores）..."
  for vmid in "${ALL_VMS[@]}"; do
    cores=$(sudo qm config "$vmid" | awk -F '[: ]+' '/^cores:/ {print $2}')
    if [[ -z "$cores" ]]; then
      cores=1
    fi
    echo "恢復 VM $vmid（cores=$cores）..."
    sudo qm set "$vmid" --cores "$cores" --delete numa0
    echo "已變更配置檔案：/etc/pve/qemu-server/${vmid}.conf"
  done
  echo "已完成所有 VM 的 pinning 恢復。"
  exit 0
fi

# 先處理 reset 個別 VM
for vmid in "${RESET_VMS[@]}"; do
  if [[ ! " ${ALL_VMS[*]} " =~ " $vmid " ]]; then
    echo "警告：VM $vmid 不存在，跳過恢復。"
    continue
  fi
  cores=$(sudo qm config "$vmid" | awk -F '[: ]+' '/^cores:/ {print $2}')
  if [[ -z "$cores" ]]; then
    cores=1
  fi
  echo "正在恢復 VM $vmid 的 pinning 設定（保留 cores=$cores）..."
  sudo qm set "$vmid" --cores "$cores" --delete numa0
  echo "已變更配置檔案：/etc/pve/qemu-server/${vmid}.conf"
done

# 處理固定 pinning
for vmid in "${ALL_VMS[@]}"; do
  if [[ -n "${FIXED_PINNING[$vmid]}" ]]; then
    cpus="${FIXED_PINNING[$vmid]}"
    cpu_count=$(echo "$cpus" | awk -F, '{print NF}')
    echo "固定分配 CPU 給 VM $vmid: $cpus (cores=$cpu_count)"
    cpus_numa="${cpus//,/;}"
    echo "執行：qm set $vmid --cpu host --cores $cpu_count --numa0 cpus=$cpus_numa"
    sudo qm set "$vmid" --cpu host --cores "$cpu_count" --numa0 cpus="$cpus_numa"
    echo "已變更配置檔案：/etc/pve/qemu-server/${vmid}.conf"
  elif [[ ! " ${RESET_VMS[*]} " =~ " $vmid " ]]; then
    echo "跳過 VM $vmid（未指定固定 CPU），保持現有設定。"
  fi
done

echo "完成指定 VM 的 CPU pinning 設定。"

EOF
sudo chmod +x /usr/local/bin/auto-vcpu-pinning.sh

echo "📂 建立 list-core-types.sh..."
sudo tee /usr/local/bin/list-core-types.sh > /dev/null << 'EOF'
#!/bin/bash
# list-core-types.sh
# 詳細列出 CPU 拓撲：P-core 主執行緒、HT、E-core，含 core_id 對應關係

echo "分析中，請稍候..."

declare -A CORE_THREADS

# 讀取 CPU、Core 對應
while IFS=',' read -r cpu core socket node; do
  [[ "$cpu" =~ ^#.*$ ]] && continue
  CORE_THREADS[$core]+="$cpu "
done < <(lscpu -p=CPU,Core,Socket,Node)

P_CORES=()
P_HTS=()
E_CORES=()
CORE_INFO=()

# 根據 thread 數量判斷 P-core / E-core，並記錄詳情
for core in $(printf "%s\n" "${!CORE_THREADS[@]}" | sort -n); do
  threads=(${CORE_THREADS[$core]})
  if [ "${#threads[@]}" -eq 2 ]; then
    sorted=($(printf '%s\n' "${threads[@]}" | sort -n))
    P_CORES+=("${sorted[0]}")
    P_HTS+=("${sorted[1]}")
    CORE_INFO+=("Core $core (P-core):     ${sorted[*]}")
  elif [ "${#threads[@]}" -eq 1 ]; then
    E_CORES+=("${threads[0]}")
    CORE_INFO+=("Core $core (E-core):     ${threads[0]}")
  else
    CORE_INFO+=("Core $core (Unknown):    ${threads[*]}")
  fi
done

# 輸出主分類
print_group() {
  local label=$1
  shift
  local sorted=($(printf '%s\n' "$@" | sort -n))
  echo "$label${sorted[*]}"
}

echo
print_group "P-core 主執行緒:  " "${P_CORES[@]}"
print_group "P-core 超執行緒: " "${P_HTS[@]}"
print_group "E-core:           " "${E_CORES[@]}"

# 輸出對應表
echo
echo "=== Core 對應表（依 core_id 排序） ==="
for line in "${CORE_INFO[@]}"; do
  echo "$line"
done

EOF
sudo chmod +x /usr/local/bin/list-core-types.sh

echo "✅ 安裝完成：/usr/local/bin/auto-vcpu-pinning.sh 與 /usr/local/bin/list-core-types.sh"
