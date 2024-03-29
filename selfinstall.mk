#
# Copyright (C) 2018 Hardkernel Co,. Ltd.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

SIGNJAR := out/host/linux-x86/framework/signapk.jar

BOOT_IMG := $(PRODUCT_OUT)/boot.img
DTBS := meson64_odroidn2_android.dtb

VENDOR := vendor.img

SELFINSTALL_DIR := $(PRODUCT_OUT)/selfinstall
SELFINSTALL_SIGNED_UPDATEPACKAGE := $(SELFINSTALL_DIR)/cache/update.zip
BOOTLOADER_MESSAGE := $(SELFINSTALL_DIR)/BOOTLOADER_MESSAGE
SELFINSTALL_CACHE_IMAGE := $(SELFINSTALL_DIR)/cache.ext4

#
# Update image : update.zip
#
UPDATE_PACKAGE_PATH := $(SELFINSTALL_DIR)/otapackages

$(SELFINSTALL_DIR)/update.unsigned.zip: bootimage cacheimage systemimage vendorimage recoveryimage productimage
	rm -rf $@
	rm -rf $(UPDATE_PACKAGE_PATH)
	mkdir -p $(UPDATE_PACKAGE_PATH)/META-INF/com/google/android
	cp -af $(PRODUCT_OUT)/system.img $(UPDATE_PACKAGE_PATH)
	cp -af $(PRODUCT_OUT)/vendor.img $(UPDATE_PACKAGE_PATH)
	cp -af $(PRODUCT_OUT)/product.img $(UPDATE_PACKAGE_PATH)
	cp -af $(INSTALLED_CACHEIMAGE_TARGET) $(UPDATE_PACKAGE_PATH)
	cp -af $(PRODUCT_OUT)/system/bin/updater \
		$(UPDATE_PACKAGE_PATH)/META-INF/com/google/android/update-binary
	cp -af $(TARGET_DEVICE_DIR)/recovery/updater-script \
		$(UPDATE_PACKAGE_PATH)/META-INF/com/google/android/updater-script
	( pushd $(UPDATE_PACKAGE_PATH); \
		zip -r $(CURDIR)/$@ * ; \
	)

$(SELFINSTALL_SIGNED_UPDATEPACKAGE): $(SELFINSTALL_DIR)/update.unsigned.zip
	mkdir -p $(dir $@)
	java \
		-Djava.library.path=out/host/linux-x86/lib64 \
		-jar $(SIGNJAR) \
		-w $(DEFAULT_KEY_CERT_PAIR).x509.pem \
		$(DEFAULT_KEY_CERT_PAIR).pk8 $< $@

$(BOOTLOADER_MESSAGE):
	mkdir -p $(dir $@)
	dd if=/dev/zero of=$@ bs=16 count=4	# 64 Bytes
	echo "recovery" >> $@
	echo "--just_exit" >> $@
	echo "--locale=en_US" >> $@
	echo "--update_package=/cache/update.zip" >> $@

.PHONY: $(SELFINSTALL_DIR)/cache
$(SELFINSTALL_DIR)/cache: $(SELFINSTALL_SIGNED_UPDATEPACKAGE) $(BOOTLOADER_MESSAGE)
	cp -af $(PRODUCT_OUT)/cache/ $(SELFINSTALL_DIR)/

$(SELFINSTALL_DIR)/cache.img: $(SELFINSTALL_DIR)/cache
	mkuserimg_mke2fs.sh -s $< $@ ext4 cache \
		$(BOARD_CACHEIMAGE_PARTITION_SIZE) -L cache

$(SELFINSTALL_CACHE_IMAGE): $(SELFINSTALL_DIR)/cache.img
	simg2img $(SELFINSTALL_DIR)/cache.img $@

#
# Android Self-Installation
#
selfinstall-$(TARGET_DEVICE).img: \
	$(BOOTLOADER_MESSAGE) \
	$(INSTALLED_RECOVERYIMAGE_TARGET) \
	build_bootloader \
	$(BOOT_IMG) \
	$(SELFINSTALL_CACHE_IMAGE)
	@echo "Creating installable single image file..."
	dd if=/dev/urandom of=$@ conv=fsync bs=512 seek=1920 count=144 # 72K Bytes
	dd if=$(PRODUCT_OUT)/u-boot.bin of=$@ conv=fsync bs=512 seek=1
	dd if=$(BOOTLOADER_MESSAGE) of=$@ conv=fsync bs=512 seek=2056
	dd if=$(PRODUCT_OUT)/hardkernel-720.bmp.gz of=$@ conv=fsync bs=512 seek=2064
	dd if=$(PRODUCT_OUT)/obj/KERNEL_OBJ/arch/arm64/boot/dts/amlogic/$(DTBS) of=$@ conv=fsync bs=512 seek=6160
	dd if=$(BOOT_IMG) of=$@ conv=fsync bs=512 seek=6416
	dd if=$(INSTALLED_RECOVERYIMAGE_TARGET) of=$@ conv=fsync bs=512 seek=39184
	dd if=$(SELFINSTALL_CACHE_IMAGE) of=$@ bs=512 seek=88336
	sync
	@echo "Done."

.PHONY: selfinstall
selfinstall: selfinstall-$(TARGET_DEVICE).img
