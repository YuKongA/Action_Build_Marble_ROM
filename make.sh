#!/bin/bash

URL="$1"
date="$2"
GITHUB_ENV="$3"
GITHUB_WORKSPACE="$4"
VENDOR_URL="$5"
IMAGE_TYPE="$6"
EXT4_RW="$7"

origin_date=$(echo ${URL} | cut -d"/" -f4)
origin_Bottom_date=$(echo ${VENDOR_URL} | cut -d"/" -f4)
ORIGN_ZIP_NAME=$(echo ${VENDOR_URL} | cut -d"/" -f5)
android_version=$(echo ${URL} | cut -d"_" -f5 | cut -d"." -f1)

device=marble

magiskboot="$GITHUB_WORKSPACE"/tools/magisk_patch/magiskboot

Start_Time() {
  Start_ns=$(date +'%s%N')
}

End_Time() {
  # 小时、分钟、秒、毫秒、纳秒
  local h min s ms ns End_ns time
  End_ns=$(date +'%s%N')
  time=$(expr $End_ns - $Start_ns)
  [[ -z "$time" ]] && return 0
  ns=${time:0-9}
  s=${time%$ns}
  if [[ $s -ge 10800 ]]; then
    echo -e "\e[1;34m - 本次$1用时: 少于100毫秒 \e[0m"
  elif [[ $s -ge 3600 ]]; then
    ms=$(expr $ns / 1000000)
    h=$(expr $s / 3600)
    h=$(expr $s % 3600)
    if [[ $s -ge 60 ]]; then
      min=$(expr $s / 60)
      s=$(expr $s % 60)
    fi
    echo -e "\e[1;34m - 本次$1用时: $h小时$min分$s秒$ms毫秒 \e[0m"
  elif [[ $s -ge 60 ]]; then
    ms=$(expr $ns / 1000000)
    min=$(expr $s / 60)
    s=$(expr $s % 60)
    echo -e "\e[1;34m - 本次$1用时: $min分$s秒$ms毫秒 \e[0m"
  elif [[ -n $s ]]; then
    ms=$(expr $ns / 1000000)
    echo -e "\e[1;34m - 本次$1用时: $s秒$ms毫秒 \e[0m"
  else
    ms=$(expr $ns / 1000000)
    echo -e "\e[1;34m - 本次$1用时: $ms毫秒 \e[0m"
  fi
}

### 系统包下载
echo -e "\e[1;31m - 开始下载系统包 \e[0m"
echo -e "\e[1;33m - 开始下载待移植包 \e[0m"
Start_Time
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${URL}
End_Time 下载待移植包
Start_Time
echo -e "\e[1;33m - 开始下载底包 \e[0m"
aria2c -x16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${VENDOR_URL}
End_Time 下载底包
### 系统包下载结束

### 解包
sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools
echo -e "\e[1;31m - 开始解包 \e[0m"
Start_Time
mkdir -p "$GITHUB_WORKSPACE"/Third_Party
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip
ZIP_NAME_Third_Party=$(echo ${URL} | cut -d"/" -f5)
7z x "$GITHUB_WORKSPACE"/$ZIP_NAME_Third_Party -r -o"$GITHUB_WORKSPACE"/Third_Party
rm -rf "$GITHUB_WORKSPACE"/$ZIP_NAME_Third_Party
7z x "$GITHUB_WORKSPACE"/${ORIGN_ZIP_NAME} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin
rm -rf "$GITHUB_WORKSPACE"/${ORIGN_ZIP_NAME}
mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
"$GITHUB_WORKSPACE"/tools/payload-dumper-go -o "$GITHUB_WORKSPACE"/Extra_dir/ "$GITHUB_WORKSPACE"/"${device}"/payload.bin >/dev/null
for image_name in mi_ext product system system_ext; do
  sudo rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$image_name.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin
End_Time 解包
echo -e "\e[1;31m - 开始分解 IMAGE \e[0m"
for i in odm vendor vendor_dlkm; do
  echo -e "\e[1;33m - 正在分解: $i \e[0m"
  Start_Time
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo "$GITHUB_WORKSPACE"/tools/extract.erofs -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x >/dev/null
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
  End_Time 分解$i.img
done
sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
for i in mi_ext product system system_ext; do
  echo -e "\e[1;33m - 正在分解: $i \e[0m"
  "$GITHUB_WORKSPACE"/tools/payload-dumper-go -o "$GITHUB_WORKSPACE"/images/ -p $i "$GITHUB_WORKSPACE"/Third_Party/payload.bin >/dev/null
  Start_Time
  cd "$GITHUB_WORKSPACE"/images
  sudo "$GITHUB_WORKSPACE"/tools/extract.erofs -i "$GITHUB_WORKSPACE"/images/$i.img -x >/dev/null
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  End_Time 分解$i.img
done
sudo rm -rf "$GITHUB_WORKSPACE"/Third_Party
### 解包结束

### 功能修复
echo -e "\e[1;31m - 开始功能修复 \e[0m"
Start_Time
# 去除 AVB2.0 校验
echo -e "\e[1;31m - 去除 AVB2.0 校验 \e[0m"
"$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vbmeta.img
"$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vbmeta_system.img
# 修改 Vendor Boot
echo -e "\e[1;31m - 修改 Vendor Boot \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/vendor_boot
cd "$GITHUB_WORKSPACE"/vendor_boot
mv -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img "$GITHUB_WORKSPACE"/vendor_boot
$magiskboot unpack -h "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img 2>&1
if [ -f ramdisk.cpio ]; then
  comp=$($magiskboot decompress ramdisk.cpio 2>&1 | grep -v 'raw' | sed -n 's;.*\[\(.*\)\];\1;p')
  if [ "$comp" ]; then
    mv -f ramdisk.cpio ramdisk.cpio.$comp
    $magiskboot decompress ramdisk.cpio.$comp ramdisk.cpio 2>&1
    if [ $? != 0 ] && $comp --help 2>/dev/null; then
      $comp -dc ramdisk.cpio.$comp >ramdisk.cpio
    fi
  fi
  mkdir -p ramdisk
  chmod 755 ramdisk
  cd ramdisk
  EXTRACT_UNSAFE_SYMLINKS=1 cpio -d -F ../ramdisk.cpio -i 2>&1
fi
## 添加 FEAS 支持 (perfmgr.ko from diting)
sudo mv -f $GITHUB_WORKSPACE/tools/added_vboot_kmods/* "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/
echo "/lib/modules/perfmgr.ko:" >>"$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/modules.dep
echo "perfmgr.ko" >>"$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/modules.load
echo "perfmgr.ko" >>"$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/modules.load.recovery
## 添加更新的内核模块 (vboot)
sudo mv -f $GITHUB_WORKSPACE/tools/updated_vboot_kmods/* "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/lib/modules/*
## 去除 A14 强制加密 (fstab)
if [[ $android_version != "13" ]]; then
  echo -e "\e[1;33m - 去除 A14 强制加密 (fstab) \e[0m"
  sudo rm -rf "$GITHUB_WORKSPACE"/tools/fstab.qcom
  sudo mv -f "$GITHUB_WORKSPACE"/tools/fstab.qcom-A14 "$GITHUB_WORKSPACE"/tools/fstab.qcom
fi
## 移除 mi_ext 和 pangu (fstab)
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  echo -e "\e[1;33m - 移除 mi_ext 和 pangu (fstab) \e[0m"
  sudo sed -i "/mi_ext/d" "$GITHUB_WORKSPACE"/tools/fstab.qcom
  sudo sed -i "/overlay/d" "$GITHUB_WORKSPACE"/tools/fstab.qcom
fi
## 添加液态 2.0 支持 (fstab)
echo -e "\e[1;31m - 添加液态 2.0 支持 (fstab) \e[0m"
sudo cp -f "$GITHUB_WORKSPACE"/tools/fstab.qcom "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
sudo chmod 644 "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/first_stage_ramdisk/fstab.qcom
## 重新打包 Vendor Boot
cd "$GITHUB_WORKSPACE"/vendor_boot/ramdisk/
find | sed 1d | cpio -H newc -R 0:0 -o -F ../ramdisk_new.cpio
cd ..
if [ "$comp" ]; then
  $magiskboot compress=$comp ramdisk_new.cpio 2>&1
  if [ $? != 0 ] && $comp --help 2>/dev/null; then
    $comp -9c ramdisk_new.cpio >ramdisk.cpio.$comp
  fi
fi
ramdisk=$(ls ramdisk_new.cpio* 2>/dev/null | tail -n1)
if [ "$ramdisk" ]; then
  cp -f $ramdisk ramdisk.cpio
  case $comp in
  cpio) nocompflag="-n" ;;
  esac
  $magiskboot repack $nocompflag "$GITHUB_WORKSPACE"/vendor_boot/vendor_boot.img "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vendor_boot.img 2>&1
fi
sudo rm -rf "$GITHUB_WORKSPACE"/vendor_boot
# 替换 Vendor 的 fstab
sudo cp -f "$GITHUB_WORKSPACE"/tools/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom
# 内置 TWRP (skkk v7.9)
echo -e "\e[1;31m - 内置 TWRP (skkk v7.9) \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/recovery.zip -d "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
# 替换官方 Boot (Melt-Kernel-marble-v2.2.7)
echo -e "\e[1;33m - 替换官方 Boot (Melt-Kernel-marble-v2.2.7) \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/boot
cd "$GITHUB_WORKSPACE"/boot
cp -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/boot.img "$GITHUB_WORKSPACE"/boot
$magiskboot unpack "$GITHUB_WORKSPACE"/boot/boot.img >/dev/null
cd "$GITHUB_WORKSPACE"/boot
rm "$GITHUB_WORKSPACE"/boot/kernel
cp -f "$GITHUB_WORKSPACE"/tools/boot_patch/Image "$GITHUB_WORKSPACE"/boot/kernel
$magiskboot repack "$GITHUB_WORKSPACE"/boot/boot.img "$GITHUB_WORKSPACE"/images/boot_patch.img >/dev/null
rm -rf "$GITHUB_WORKSPACE"/boot
# 修改 Vendor DLKM
echo -e "\e[1;31m - 修改 Vendor DLKM \e[0m"
## 移除无用的内核模块
unneeded_kmods='atmel_mxt_ts.ko cameralog.ko coresight-csr.ko coresight-cti.ko coresight-dummy.ko coresight-funnel.ko coresight-hwevent.ko coresight-remote-etm.ko coresight-replicator.ko coresight-stm.ko coresight-tgu.ko coresight-tmc.ko coresight-tpda.ko coresight-tpdm.ko coresight.ko cs35l41_dlkm.ko f_fs_ipc_log.ko focaltech_fts.ko icnss2.ko nt36xxx-i2c.ko nt36xxx-spi.ko qca_cld3_qca6750.ko qcom-cpufreq-hw-debug.ko qcom_iommu_debug.ko qti_battery_debug.ko rdbg.ko spmi-glink-debug.ko spmi-pmic-arb-debug.ko stm_console.ko stm_core.ko stm_ftrace.ko stm_p_basic.ko stm_p_ost.ko synaptics_dsx.ko'
for i in $unneeded_kmods; do
  sudo rm -rf "$GITHUB_WORKSPACE/${device}/vendor_dlkm/lib/modules/$i"
  sed -i "/$i/d" "$GITHUB_WORKSPACE/${device}/vendor_dlkm/lib/modules/modules.load"
done
## 添加更新的内核模块 (Kernel Modules from Melt-Kernel-marble-v2.2.7)
sudo mv -f $GITHUB_WORKSPACE/tools/updated_dlkm_kmods/* "$GITHUB_WORKSPACE"/"${device}"/vendor_dlkm/lib/modules/
# 添加 Root (刷入时可自行选择)
echo -e "\e[1;31m - 添加 ROOT (刷入时可自行选择) \e[0m"
## 修补 Magisk 26.1 (Official)
echo -e "\e[1;33m - 修补 Magisk 26.1 (Official) \e[0m"
sh "$GITHUB_WORKSPACE"/tools/magisk_patch/boot_patch.sh "$GITHUB_WORKSPACE"/images/boot_patch.img
mv "$GITHUB_WORKSPACE"/tools/magisk_patch/new-boot.img "$GITHUB_WORKSPACE"/images/boot_magisk.img
## Patch KernelSU
echo -e "\e[1;33m - Patch KernelSU \e[0m"
mkdir -p "$GITHUB_WORKSPACE"/boot
cd "$GITHUB_WORKSPACE"/boot
cp -f "$GITHUB_WORKSPACE"/"${device}"/firmware-update/boot.img "$GITHUB_WORKSPACE"/boot
cp -f "$GITHUB_WORKSPACE"/tools/kernelsu_patch/bspatch "$GITHUB_WORKSPACE"/boot
cp -f "$GITHUB_WORKSPACE"/tools/kernelsu_patch/ksu.p "$GITHUB_WORKSPACE"/boot
$magiskboot unpack "$GITHUB_WORKSPACE"/boot/boot.img >/dev/null
mv "$GITHUB_WORKSPACE"/tools/boot_patch/Image "$GITHUB_WORKSPACE"/boot/kernel
"$GITHUB_WORKSPACE"/boot/bspatch "$GITHUB_WORKSPACE"/boot/kernel "$GITHUB_WORKSPACE"/boot/kernel "$GITHUB_WORKSPACE"/boot/ksu.p
$magiskboot repack "$GITHUB_WORKSPACE"/boot/boot.img "$GITHUB_WORKSPACE"/images/boot_kernelsu.img >/dev/null
rm -rf "$GITHUB_WORKSPACE"/boot
# 添加 FEAS 支持 (libmigui/joyose)
$magiskboot hexpatch "$GITHUB_WORKSPACE"/images/system_ext/lib64/libmigui.so 726F2E70726F647563742E70726F647563742E6E616D65 726F2E70726F647563742E70726F646375742E6E616D65
for product_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/product -type f -name "build.prop"); do
  sudo sed -i ''"$(sudo sed -n '/ro.product.product.name/=' "$product_build_prop")"'a ro.product.prodcut.name=diting' "$product_build_prop"
done
for joyose_files in $(sudo find "$GITHUB_WORKSPACE"/images/product/pangu/system/ -iname "*joyose_files*"); do
  echo -e "\e[1;33m - 找到文件: $joyose_files \e[0m"
  sudo rm -rf "$joyose_files"
done
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/Joyose.zip -d "$GITHUB_WORKSPACE"/images/product/pangu/system/
# 替换 Overlay 叠加层
echo -e "\e[1;31m - 替换 Overlay 叠加层 \e[0m"
if [[ $android_version == "13" ]]; then
  sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/*
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
else
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay-A14.zip -d "$GITHUB_WORKSPACE"/images/product/overlay
fi
# 添加 MIUI 新壁纸
echo -e "\e[1;31m - 添加 MIUI 新壁纸 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/media/wallpaper/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/wallpaper_group.zip -d "$GITHUB_WORKSPACE"/images/product/media/
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/wallpaper_group1.zip -d "$GITHUB_WORKSPACE"/images/product/media/
# 恢复红米开机动画
# echo -e "\e[1;31m - 恢复红米开机动画 \e[0m"
# sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/bootanimation.zip -d "$GITHUB_WORKSPACE"/images/product/media/
# 禁用恢复预置应用提示
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/auto-install.json "$GITHUB_WORKSPACE"/images/product/etc/
# 添加 device_features 文件
echo -e "\e[1;31m - 添加 device_features 文件 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/
# 修改 build.prop
echo -e "\e[1;31m - 修改 build.prop \e[0m"
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)
sudo sed -i 's/ro.build.user=[^*]*/ro.build.user=YuKongA/' "$GITHUB_WORKSPACE"/images/system/system/build.prop
origin_date=$(sudo cat "$GITHUB_WORKSPACE"/images/system/system/build.prop | grep 'ro.build.version.incremental=' | cut -d '=' -f 2)
for date_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop'); do
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$date_build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$date_build_prop"
  sudo sed -i 's/'"${origin_date}"'/'"${date}"'/g' "$date_build_prop"
done
if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
  for erofs_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ext4' | sed 's/^\.\///' | sort); do
    sudo sed -i 's/ext4//g' "$erofs_build_prop"
  done
fi
for build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/'"${origin_Bottom_date}"'/'"${date}"'/' "$build_prop"
  sudo sed -i 's/build.date=[^*]*/build.date='"$build_time"'/' "$build_prop"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"$build_utc"'/' "$build_prop"
done
## 添加性能等级支持
for odm_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/odm -type f -name "build.prop"); do
  sudo sed -i ''"$(sudo sed -n '/ro.odm.build.version.sdk/=' "$odm_build_prop")"'a ro.odm.build.media_performance_class=33' "$odm_build_prop"
done
## 去除指纹位置指示
if [[ $android_version == "14" ]]; then
  sudo sed -i s/ro.hardware.fp.sideCap=true/ro.hardware.fp.sideCap=false/g "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
fi
rom_security=$(sudo cat "$GITHUB_WORKSPACE"/images/system/system/build.prop | grep 'ro.build.version.security_patch=' | cut -d '=' -f 2)
sudo sed -i 's/ro.vendor.build.security_patch=[^*]*/ro.vendor.build.security_patch='"$rom_security"'/' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
rom_name=$(sudo cat "$GITHUB_WORKSPACE"/images/product/etc/build.prop | grep 'ro.product.product.name=' | cut -d '=' -f 2)
sudo sed -i 's/'"$rom_name"'/marble/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
# 替换小米 13 的部分震动效果
echo -e "\e[1;31m - 移植小米 13 的清理震动效果 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/vibrator_firmware.zip -d "$GITHUB_WORKSPACE"/"${device}"/vendor/firmware/
# 精简部分应用
echo -e "\e[1;31m - 精简部分应用 \e[0m"
for files in MIGalleryLockscreen MIUIDriveMode MIUIDuokanReader MIUIGameCenter MIUINewHome MIUIYoupin MIUIHuanJi MIUIMiDrive MIUIVirtualSim ThirdAppAssistant XMRemoteController MIUIVipAccount MiuiScanner Xinre SmartHome MiShop MiRadio MIUICompass MediaEditor BaiduIME iflytek.inputmethod MIService MIUIEmail MIUIVideo MIUIMusicT; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${files}*")
  if [[ $appsui != "" ]]; then
    echo -e "\e[1;33m - 找到精简目录: $appsui \e[0m"
    sudo rm -rf $appsui
  fi
done
# 分辨率修改
echo -e "\e[1;31m - 分辨率修改 \e[0m"
Find_character() {
  FIND_FILE="$1"
  FIND_STR="$2"
  if [ $(grep -c "$FIND_STR" $FIND_FILE) -ne '0' ]; then
    Character_present=true
    echo -e "\e[1;33m - 找到指定字符: $2 \e[0m"
  else
    Character_present=false
    echo -e "\e[1;33m - !未找到指定字符: $2 \e[0m"
  fi
}
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop persist.miui.density_v2
if [[ $Character_present == true ]]; then
  sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=440/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a persist.miui.density_v2=440' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi
# Millet 修复
echo -e "\e[1;31m - Millet 修复 \e[0m"
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop ro.millet.netlink
if [[ $Character_present == true ]]; then
  sudo sed -i 's/ro.millet.netlink=[^*]*/ro.millet.netlink=30/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a ro.millet.netlink=30' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi
# 替换音质音效
for Sound in $(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*MiSound*"); do
  echo -e "\e[1;31m - 替换音质音效 \e[0m"
  sudo rm -rf $Sound
done
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/MiSound.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 替换小爱翻译 v3.2.3 (支持在线字幕)
for Aiasst in $(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*aiasstvision*"); do
  echo -e "\e[1;31m - 替换小爱翻译 v3.2.3 (支持在线字幕) \e[0m"
  sudo rm -rf $Aiasst
done
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/AiasstVision.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 替换相机标定
echo -e "\e[1;31m - 替换相机标定 \e[0m"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/CameraTools_beta.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 部分机型指纹支付相关服务存在于 Product，需要清除
echo -e "\e[1;31m - 清除多余指纹支付服务 \e[0m"
for files in IFAAService MipayService SoterService TimeService; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*${files}*")
  if [[ $appsui != "" ]]; then
    echo -e "\e[1;33m - 找到服务目录: $appsui \e[0m"
    sudo rm -rf $appsui
  fi
done
# 占位毒瘤和广告
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/AnalyticsCore.apk "$GITHUB_WORKSPACE"/images/product/app/AnalyticsCore
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA
# 常规修改
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/DeviceConfig.apk || true
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/overlay/SettingsRroDeviceSystemUiOverlay.apk || true
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images
if [[ $android_version == "13" ]]; then
  # 添加相机 4K60FPS 支持
  echo -e "\e[1;31m - 添加相机 4K60FPS 支持 \e[0m"
  sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/*
  sudo cat "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.1.apk "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.2.apk >"$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk
  sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/
else
  # A14 相机修复
  echo -e "\e[1;31m - A14 相机修复 \e[0m"
  sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/*
  sudo cat "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.A14.z* >"$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.zip
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.zip -d "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/
fi
# 移除 Android 签名校验
sudo mkdir -p "$GITHUB_WORKSPACE"/apk/
Apktool="java -jar "$GITHUB_WORKSPACE"/tools/apktool.jar"
echo -e "\e[1;31m - 开始移除 Android 签名校验 \e[0m"
sudo cp -rf "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar "$GITHUB_WORKSPACE"/apk/services.apk
echo -e "\e[1;33m - 开始反编译 \e[0m"
cd "$GITHUB_WORKSPACE"/apk
sudo $Apktool d -q "$GITHUB_WORKSPACE"/apk/services.apk
fbynr='getMinimumSignatureSchemeVersionForTargetSdk'
sudo find "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/ "$GITHUB_WORKSPACE"/apk/services/smali_classes2/com/android/server/pm/pkg/parsing/ -type f -maxdepth 1 -name "*.smali" -exec grep -H "$fbynr" {} \; | cut -d ':' -f 1 | while read i; do
  hs=$(grep -n "$fbynr" "$i" | cut -d ':' -f 1)
  sz=$(sudo tail -n +"$hs" "$i" | grep -m 1 "move-result" | tr -dc '0-9')
  hs1=$(sudo awk -v HS=$hs 'NR>=HS && /move-result /{print NR; exit}' "$i")
  hss=$hs
  sedsc="const/4 v${sz}, 0x0"
  { sudo sed -i "${hs},${hs1}d" "$i" && sudo sed -i "${hss}i\\${sedsc}" "$i"; } && echo -e "\e[1;33m - ${i}  修改成功 \e[0m"
done
echo -e "\e[1;33m - 反编译成功，开始回编译 \e[0m"
cd "$GITHUB_WORKSPACE"/apk/services/
sudo $Apktool b -q -f -c "$GITHUB_WORKSPACE"/apk/services/ -o services.jar
sudo cp -rf "$GITHUB_WORKSPACE"/apk/services/services.jar "$GITHUB_WORKSPACE"/images/system/system/framework/services.jar
# 人脸修复
echo -e "\e[1;31m - 人脸修复 \e[0m"
for MiuiBiometric in $(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*MiuiBiometric*"); do
  sudo rm -rf $MiuiBiometric
done
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/face.zip -d "$GITHUB_WORKSPACE"/images/product/app/
# 恢复自定义高刷应用支持
if [[ $android_version == "13" ]]; then
  echo -e "\e[1;31m - 恢复自定义高刷应用支持 \e[0m"
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/libpower.zip -d "$GITHUB_WORKSPACE"/images/system/system/
fi
# 修复自动亮度/移除高温降亮度
echo -e "\e[1;31m - 自动亮度修复 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/displayconfig.zip -d "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/
# 替换回旧的 02 屏幕调色配置
echo -e "\e[1;31m - 替换回旧的 02 屏幕调色配置 \e[0m"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/display/qdcm_calib_data_xiaomi_36_02_0a_video_mode_dsc_dsi_panel.json
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/02_dsi_panel.zip -d "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/display/
# 修复机型为 POCO 时最近任务崩溃
echo -e "\e[1;31m - 修复机型为 POCO 时最近任务崩溃 \e[0m"
sudo sed -i 's/com.mi.android.globallauncher/com.miui.home/' "$GITHUB_WORKSPACE"/images/system_ext/etc/init/init.miui.ext.rc
# NFC 修复
if [[ $android_version == "13" ]]; then
  echo -e "\e[1;31m - NFC 修复 \e[0m"
  for nfc_files in $(sudo find "$GITHUB_WORKSPACE"/images/product/pangu/system/ -iname "*nfc*"); do
    echo -e "\e[1;33m - 找到文件: $nfc_files \e[0m"
    sudo rm -rf "$nfc_files"
  done
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/nfc.zip -d "$GITHUB_WORKSPACE"/images/product/pangu/system/
fi
# ext4_rw 修改
if [[ "${IMAGE_TYPE}" == "ext4" && "${EXT4_RW}" == "true" ]]; then
  ## 移除 mi_ext 和 pangu (product)
  pangu="$GITHUB_WORKSPACE"/images/product/pangu/system
  sudo find "$pangu" -type d | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
  sudo find "$pangu" -type f | sed 's/\./\\./g' | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
  sudo cp -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/* "$GITHUB_WORKSPACE"/images/system/system/
  sudo rm -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/*
fi
# 系统更新获取更新路径对齐
echo -e "\e[1;31m - 系统更新获取更新路径对齐 \e[0m"
for mod_device_build in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ro.product.mod_device=' | sed 's/^\.\///' | sort); do
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=marble/' "$mod_device_build"
  else
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=marble_pre/' "$mod_device_build"
  fi
done
# 替换我的设备图片
# echo -e "\e[1;31m - 替换我的设备图片 \e[0m"
# sudo mv -f  "$GITHUB_WORKSPACE"/"${device}"_files/com.android.settings "$GITHUB_WORKSPACE"/images/product/media/theme/default/
# 替换更改文件/删除多余文件
echo -e "\e[1;31m - 替换更改文件/删除多余文件 \e[0m"
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images
sudo rm -rf "$GITHUB_WORKSPACE"/images/firmware-update/boot.img
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img
echo -e "\e[1;31m - 开始打包 IMAGE \e[0m"
if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    echo -e "\e[1;31m - 正在生成: $i \e[0m"
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts
    Start_Time
    sudo "$GITHUB_WORKSPACE"/tools/mkfs.erofs -zlz4hc,9 -T 1230768000 --mount-point /$i --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts "$GITHUB_WORKSPACE"/images/$i.img "$GITHUB_WORKSPACE"/images/$i >/dev/null
    End_Time 打包erofs
    eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
  done
  sudo rm -rf "$GITHUB_WORKSPACE"/images/config
  Start_Time
  "$GITHUB_WORKSPACE"/tools/lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:9663676416 --metadata-slots 3 --group qti_dynamic_partitions_a:9663676416 --group qti_dynamic_partitions_b:9663676416 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
  End_Time 打包super
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  done
elif [[ "${IMAGE_TYPE}" == "ext4" ]]; then
  img_free() {
    size_free="$(tune2fs -l "$GITHUB_WORKSPACE"/images/${i}.img | awk '/Free blocks:/ { print $3 }')"
    size_free="$(echo "$size_free / 4096 * 1024 * 1024" | bc)"
    if [[ $size_free -ge 1073741824 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1073741824}")G
    elif [[ $size_free -ge 1048576 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1048576}")MB
    elif [[ $size_free -ge 1024 ]]; then
      File_Type=$(awk "BEGIN{print $size_free/1024}")kb
    elif [[ $size_free -le 1024 ]]; then
      File_Type=${size_free}b
    fi
    echo -e "\e[1;33m - ${i}.img 剩余空间: $File_Type \e[0m"
  }
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    eval "$i"_size_orig=$(sudo du -sb "$GITHUB_WORKSPACE"/images/$i | awk {'print $1'})
    if [[ "$(eval echo "$"$i"_size_orig")" -lt "104857600" ]]; then
      size=$(echo "$(eval echo "$"$i"_size_orig") * 15 / 10 / 4096 * 4096" | bc)
    elif [[ "$(eval echo "$"$i"_size_orig")" -lt "1073741824" ]]; then
      size=$(echo "$(eval echo "$"$i"_size_orig") * 108 / 100 / 4096 * 4096" | bc)
    else
      size=$(echo "$(eval echo "$"$i"_size_orig") * 103 / 100 / 4096 * 4096" | bc)
    fi
    eval "$i"_size=$(echo "$size * 4096 / 4096 / 4096" | bc)
  done
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    mkdir -p "$GITHUB_WORKSPACE"/images/$i/lost+found
    sudo touch -t 200901010000.00 "$GITHUB_WORKSPACE"/images/$i/lost+found
  done
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    echo -e "\e[1;31m - 正在生成: $i \e[0m"
    sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config
    sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$i "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts
    eval "$i"_inode=$(sudo cat "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config | wc -l)
    eval "$i"_inode=$(echo "$(eval echo "$"$i"_inode") + 8" | bc)
    "$GITHUB_WORKSPACE"/tools/mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$i.img $(eval echo "$"$i"_size") || false
    Start_Time
    if [[ "${EXT4_RW}" == "true" ]]; then
      sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i "$GITHUB_WORKSPACE"/images/$i.img || false
    else
      sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i -s "$GITHUB_WORKSPACE"/images/$i.img || false
    fi
    End_Time 打包"$i".img
    resize2fs -f -M "$GITHUB_WORKSPACE"/images/$i.img
    eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
    img_free
    if [[ $i == mi_ext ]]; then
      sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
      continue
    fi
    size_free=$(tune2fs -l "$GITHUB_WORKSPACE"/images/$i.img | awk '/Free blocks:/ { print $3}')
    # 第二次打包 (不预留空间)
    if [[ "$size_free" != 0 && "${EXT4_RW}" != "true" ]]; then
      size_free=$(echo "$size_free * 4096" | bc)
      eval "$i"_size=$(echo "$(eval echo "$"$i"_size") - $size_free" | bc)
      eval "$i"_size=$(echo "$(eval echo "$"$i"_size") * 4096 / 4096 / 4096" | bc)
      sudo rm -rf "$GITHUB_WORKSPACE"/images/$i.img
      echo -e "\e[1;31m - 二次生成: $i \e[0m"
      "$GITHUB_WORKSPACE"/tools/mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$i.img $(eval echo "$"$i"_size") || false
      Start_Time
      if [[ "${EXT4_RW}" == "true" ]]; then
        sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i "$GITHUB_WORKSPACE"/images/$i.img || false
      else
        sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i -s "$GITHUB_WORKSPACE"/images/$i.img || false
      fi
      End_Time 二次打包"$i".img
      resize2fs -f -M "$GITHUB_WORKSPACE"/images/$i.img
      eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
      img_free
    fi
    # 第二次打包 (除 mi_ext/vendor_dlkm 外各预留 100M 空间)
    if [[ "${EXT4_RW}" == "true" ]]; then
      if [[ $i != mi_ext && $i != vendor_dlkm ]]; then
        eval "$i"_size=$(echo "$(eval echo "$"$i"_size") + 104857600" | bc)
        eval "$i"_size=$(echo "$(eval echo "$"$i"_size") * 4096 / 4096 / 4096" | bc)
        sudo rm -rf "$GITHUB_WORKSPACE"/images/$i.img
        echo -e "\e[1;31m - 二次生成: $i \e[0m"
        "$GITHUB_WORKSPACE"/tools/mke2fs -O ^has_journal -L $i -I 256 -N $(eval echo "$"$i"_inode") -M /$i -m 0 -t ext4 -b 4096 "$GITHUB_WORKSPACE"/images/$i.img $(eval echo "$"$i"_size") || false
        Start_Time
        if [[ "${EXT4_RW}" == "true" ]]; then
          sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i "$GITHUB_WORKSPACE"/images/$i.img || false
        else
          sudo "$GITHUB_WORKSPACE"/tools/e2fsdroid -e -T 1230768000 -C "$GITHUB_WORKSPACE"/images/config/"$i"_fs_config -S "$GITHUB_WORKSPACE"/images/config/"$i"_file_contexts -f "$GITHUB_WORKSPACE"/images/$i -a /$i -s "$GITHUB_WORKSPACE"/images/$i.img || false
        fi
        End_Time 二次打包"$i".img
        eval "$i"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$i.img | awk {'print $1'})
        img_free
      fi
    fi
    sudo rm -rf "$GITHUB_WORKSPACE"/images/$i
  done
  sudo rm -rf "$GITHUB_WORKSPACE"/images/config
  sudo rm -rf "$GITHUB_WORKSPACE"/images/mi_ext
  Start_Time
  "$GITHUB_WORKSPACE"/tools/lpmake --metadata-size 65536 --super-name super --block-size 4096 --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a --image odm_a="$GITHUB_WORKSPACE"/images/odm.img --partition odm_b:readonly:0:qti_dynamic_partitions_b --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a --image product_a="$GITHUB_WORKSPACE"/images/product.img --partition product_b:readonly:0:qti_dynamic_partitions_b --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a --image system_a="$GITHUB_WORKSPACE"/images/system.img --partition system_b:readonly:0:qti_dynamic_partitions_b --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img --partition system_ext_b:readonly:0:qti_dynamic_partitions_b --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img --partition vendor_b:readonly:0:qti_dynamic_partitions_b --partition vendor_dlkm_a:readonly:"$vendor_dlkm_size":qti_dynamic_partitions_a --image vendor_dlkm_a="$GITHUB_WORKSPACE"/images/vendor_dlkm.img --partition vendor_dlkm_b:readonly:0:qti_dynamic_partitions_b --device super:9663676416 --metadata-slots 3 --group qti_dynamic_partitions_a:9663676416 --group qti_dynamic_partitions_b:9663676416 --virtual-ab -F --output "$GITHUB_WORKSPACE"/images/super.img
  End_Time 打包super
  for i in mi_ext odm product system system_ext vendor vendor_dlkm; do
    rm -rf "$GITHUB_WORKSPACE"/images/$i.img
  done
fi
### 生成 super.img 结束

### 生成卡刷包
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -9 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
### 生成卡刷包结束

### 定制 ROM 包名
if [[ "${device}" == "marble" ]]; then
  sudo 7z a "$GITHUB_WORKSPACE"/zip/miui_MARBLE_${date}.zip "$GITHUB_WORKSPACE"/images/*
  sudo rm -rf "$GITHUB_WORKSPACE"/images
  md5=$(md5sum "$GITHUB_WORKSPACE"/zip/miui_MARBLE_${date}.zip)
  echo "MD5=${md5:0:32}" >>$GITHUB_ENV
  zipmd5=${md5:0:10}
  rom_name="miui_"
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    rom_name+="MARBLE_"
  else
    rom_name+="MARBLEPRE_"
  fi
  rom_name+="${date}_${zipmd5}_${android_version}.0"
  if [[ "${IMAGE_TYPE}" == "erofs" ]]; then
    rom_name+="_EROFS"
  else
    rom_name+="_EXT4"
    if [[ "${EXT4_RW}" == "true" ]]; then
      rom_name+="_RW"
    fi
  fi
  rom_name+=".zip"
  sudo mv "$GITHUB_WORKSPACE"/zip/miui_MARBLE_${date}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
  echo "NEW_PACKAGE_NAME="${rom_name}"" >>$GITHUB_ENV
fi
### 定制 ROM 包名结束
