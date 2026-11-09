#!/usr/bin/env bash
# Build gbxminer for NVIDIA GH200 (Grace aarch64 + Hopper sm_90).
#
# - Uses the system CUDA toolkit under /usr (Ubuntu nvidia-cuda-toolkit 12.8),
#   matching driver 570 (max CUDA 12.8). A newer toolkit (e.g. 12.9) would emit
#   PTX the driver can't JIT, breaking NVRTC algos such as kawpow/firopow.
#   Override with CUDA_HOME=/path/to/cuda.
# - Only compiles sm_90 (+ compute_90 PTX): much faster build, native SASS.
# - Uses -mcpu=native instead of x86-only tuning flags.
set -euo pipefail
cd "$(dirname "$0")"

CUDA_HOME="${CUDA_HOME:-/usr}"
CUDA_ARCH="${CUDA_ARCH:-90}"

make distclean >/dev/null 2>&1 || true
./autogen.sh >/dev/null

CUDA_CFLAGS="-O3 -lineno -Xcompiler -Wall -D_FORCE_INLINES" \
./configure \
    CXXFLAGS="-O3 -mcpu=native -D_REENTRANT" \
    CFLAGS="-O3 -mcpu=native" \
    --with-cuda="$CUDA_HOME" \
    --with-cuda-arch="$CUDA_ARCH" \
    --with-nvml=libnvidia-ml.so \
    --with-nvrtc

make -j"$(nproc)"

file ./gbxminer
./gbxminer --version || true
