# auto-vcpu-pinning.sh
#
## 功能：
 1. 無參數時，列出所有 VM 的 vCPU 配置（cores, sockets, cpu, numa）。
 2. 根據輸入參數，固定分配指定 VM 的 CPU 核心。
    輸入格式：VMID:cpu1,cpu2,...
    例如：./auto-vcpu-pinning.sh 812:14,15 820:10,11,12,13
 3. 支援 --reset VMID，用於恢復該 VM 的 CPU pinning（保留 cores 原設定）。
 4. 支援 --reset all，恢復所有 VM 的 CPU pinning（保留 cores 原設定）。
 5. 自動計算 cores 數量，並用 --numa0 cpus= 指定 CPU 核心（用分號分隔）。
 6. 其他未指定的 VM 保持現有設定，不做修改，只顯示跳過提示。
## 增強功能：
 1. 同時設置 numa0 cpus 和嚴格 CPU affinity
 2. 支持顯示當前 affinity 狀態
 3. 重置時會清除 affinity 設置
 4. 更好的錯誤處理和用戶提示

## 使用環境：
 - 需在 Proxmox VE 主機上以 root 或 sudo 權限執行。
 - 使用 qm 命令管理虛擬機。

## 注意事項：
 - CPU 核心 ID 請自行確認對應正確。
 - numa0 設定會覆蓋 NUMA 配置，請確保此操作對虛擬機運行無負面影響。
 - CPU 核心 ID 間用逗號分隔，內部會轉成分號以符合 qm 指令格式。



# list-core-types.sh
 詳細列出 CPU 拓撲：P-core 主執行緒、HT、E-core，含 core_id 對應關係


## 🚀 一鍵安裝指令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liweileeliweilee/auto-vcpu-pinning/main/setup-auto-vcpu-pinning.sh)
```
## 🚀 一鍵解除安裝指令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liweileeliweilee/auto-vcpu-pinning/main/uninstall-auto-vcpu-pinning.sh)
```
