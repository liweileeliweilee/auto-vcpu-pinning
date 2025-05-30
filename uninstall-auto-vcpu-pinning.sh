#!/bin/bash

set -e

echo "🧹 移除 /usr/local/bin/auto-vcpu-pinning.sh..."
sudo rm -f /usr/local/bin/auto-vcpu-pinning.sh

echo "🧹 移除 /usr/local/bin/list-core-types.sh..."
sudo rm -f /usr/local/bin/list-core-types.sh

echo "✅ 已移除 auto-vcpu-pinning 相關腳本。"
