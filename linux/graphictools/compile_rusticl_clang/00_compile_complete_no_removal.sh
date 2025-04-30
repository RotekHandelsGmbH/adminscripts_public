#!/usr/bin/env bash
set -euo pipefail

./10_create_build_env.sh
./15_build_libdrm.sh
./20_build_spirv_tools.sh
./30_build_spirv_llvm_translator.sh
./40_build_libclc.sh
./50_build_mesa.sh
./60_cleanup_icds.sh
./70_write_env_profile.sh
python3 80_check_amd_gpu.py
