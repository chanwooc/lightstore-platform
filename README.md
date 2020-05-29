# LightStore Platform
This repo builds hardware/FPGA images for LightStore-based systems.

# Supported Boards
- ARM-based system: \[Xilinx ZCU102: ARM & FPGA\] + \[MIT CSG Custom Flash Card\]
- x86-based system: \[x86 Host\] + \[Xilinx VC707 or VCU108: FPGA\] + \[MIT CSG Custom Flash Card\]

# PinK Project Specifics
PinK is an ARM-based KV-SSD running LSM-Tree based on the ARM-based LightStore platform.
[PinK Software](https://github.com/kukania/PinK) runs on the ZCU102 ARM cores and the ZCU102 board becomes a standalone KV-SSD.

PinK uses a hardware keytable merger (modules/keytable\_merger)

# Building PinK FPGA image

Bluespec compiler and Xilinx Vivado are required.

After initializaing submodules, build the hardware image under `projects/pink`
```
make -j8 build.zcu102
```

