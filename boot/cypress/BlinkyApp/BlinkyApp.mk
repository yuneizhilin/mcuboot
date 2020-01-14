################################################################################
# \file targets.mk
# \version 1.0
#
# \brief
# Makefile to describe supported boards and platforms for Cypress MCUBoot based applications.
#
################################################################################
# \copyright
# Copyright 2018-2019 Cypress Semiconductor Corporation
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

# Cypress' MCUBoot Application supports GCC ARM only at this moment
# Set defaults to:
# 	- compiler GCC
#   - build configuration to Debug
#   - image type to BOOT
COMPILER ?= GCC_ARM
IMG_TYPE ?= BOOT

# image type can be BOOT or UPGRADE
IMG_TYPES = BOOT UPGRADE

# BlinkyApp will be be run by CyBootloader wih multi image support
MULTI_IMAGE ?= 1

# CypressBootloader Image ID to use for signing
CYB_IMG_ID ?= 16

ifneq ($(COMPILER), GCC_ARM)
$(error Only GCC ARM is supported at this moment)
endif

CUR_APP_PATH = $(CURDIR)/$(APP_NAME)

include $(CUR_APP_PATH)/targets.mk
include $(CUR_APP_PATH)/libs.mk
include $(CUR_APP_PATH)/toolchains.mk

# Application-specific DEFINES
ifeq ($(IMG_TYPE), BOOT)
	DEFINES_APP := -DBOOT_IMG
else
	DEFINES_APP := -DUPGRADE_IMG
endif

# Define start of application as it can be built for Secure Boot target
# Also check if this image will be used with multi image CyBootloader
ifneq ($(filter $(TARGET), $(SB_TARGETS)),)
	ifeq ($(MULTI_IMAGE), 0)
		DEFINES_APP += -DUSER_APP_START=0x10000000
        SLOT_SIZE ?= 0x50000
	else
		DEFINES_APP += -DUSER_APP_START=0x10020000
        SLOT_SIZE ?= 0x10000
	endif
else
	DEFINES_APP += -DUSER_APP_START=0x10018000
    SLOT_SIZE ?= 0x10000
endif

# Collect Test Application sources
SOURCES_APP_SRC := $(wildcard $(CUR_APP_PATH)/*.c)
# Collect all the sources
SOURCES_APP += $(SOURCES_APP_SRC)

# Collect includes for BlinkyApp
INCLUDE_DIRS_APP := $(addprefix -I, $(CURDIR))
INCLUDE_DIRS_APP += $(addprefix -I, $(CUR_APP_PATH))

# Overwite path to linker script if custom is required, otherwise default from BSP is used
ifeq ($(COMPILER), GCC_ARM)
LINKER_SCRIPT := $(subst /cygdrive/c,c:,$(CUR_APP_PATH)/linker/$(APP_NAME).ld)
else
$(error Only GCC ARM is supported at this moment)
endif

ASM_FILES_APP :=

IMGTOOL_PATH ?=	../../scripts/imgtool.py

SIGN_ARGS := sign --header-size 1024 --pad-header --align 8 -v "2.0" -S $(SLOT_SIZE) -M 512 --overwrite-only -R 0 -k keys/$(SIGN_KEY_FILE).pem

# Set build directory for BOOT and UPGRADE images
ifeq ($(IMG_TYPE), UPGRADE)
	SIGN_ARGS += --pad
	UPGRADE_SUFFIX :=_upgrade

# Output folder
OUT := $(APP_NAME)/out
# Output folder to contain build artifacts
OUT_TARGET := $(OUT)/$(TARGET)

OUT_CFG := $(OUT_TARGET)/$(BUILDCFG)

# Set build directory for BOOT and UPGRADE images
ifeq ($(IMG_TYPE), BOOT)
	OUT_CFG := $(OUT_CFG)/boot
else
	OUT_CFG := $(OUT_CFG)/upgrade
else
	OUT_CFG := $(OUT_CFG)/boot
endif

# Determine path to policy file if multi image is used
ifeq ($(MULTI_IMAGE), 1)
	MULTI_IMAGE_POLICY := $(CY_SEC_TOOLS_PATH)/cysecuretools/targets/cy8ckit_064x0s2_4343w/policy/policy_single_stage_multi_img_CM0p_CM4_debug.json
endif

pre_build:
	$(info [PRE_BUILD] - Generating linker script for application $(CUR_APP_PATH)/linker/$(APP_NAME).ld)
	@$(CC) -E -x c $(CFLAGS) $(INCLUDE_DIRS) $(CUR_APP_PATH)/linker/$(APP_NAME)_template.ld | grep -v '^#' >$(CUR_APP_PATH)/linker/$(APP_NAME).ld

# Post build action to execute after main build job
post_build: $(OUT_CFG)/$(APP_NAME).hex
	$(info [POST_BUILD] - Executing post build script for $(APP_NAME))
# determine if target is Secure Boot - use cysecuretools for signing. built in imgtool for non secure targets
ifneq ($(filter $(TARGET), $(SB_TARGETS)),)
ifeq ($(MULTI_IMAGE), 1)
	$(PYTHON_PATH) -c "from cysecuretools import CySecureTools; tools = CySecureTools('cy8ckit-064b0s2-4343w', '$(MULTI_IMAGE_POLICY)'); tools.sign_image('$(OUT_CFG)/$(APP_NAME).hex', $(CYB_IMG_ID))"
else
	$(PYTHON_PATH) -c "from cysecuretools import CySecureTools; tools = CySecureTools('cy8ckit-064b0s2-4343w'); tools.sign_image('$(OUT_CFG)/$(APP_NAME).hex')"
endif
else
	mv -f $(OUT_CFG)/$(APP_NAME).hex $(OUT_CFG)/$(APP_NAME)_unsigned.hex
	$(PYTHON_PATH) $(IMGTOOL_PATH) $(SIGN_ARGS) $(OUT_CFG)/$(APP_NAME)_unsigned.hex $(OUT_CFG)/$(APP_NAME)$(UPGRADE_SUFFIX).hex
endif
