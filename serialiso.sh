#!/bin/bash
# Enable the serial console on a a Dell Repository Manager firmware ISO
BAUD=115200
TERMINAL=ttyS0

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

cleanup() {
  echo "Cleaning up"
  if [[ -e tmp/mount ]] && mountpoint -q tmp/mount; then
    echo Unmounting ISO
    umount tmp/mount
  fi
  rm -rf tmp
}
#trap cleanup EXIT

command -v genisoimage >/dev/null 2>&1 || { echo "genisoimage is required but not installed (aptitude install -y genisoimage)" >&2; exit 1; }

if [[ $# -ne 2 ]]; then
  echo "Pass path to ISO and output ISO as arguments"
  exit 1
fi

ISO=$1
DEST=$2

if [[ ! -f "$ISO" ]]; then
  echo ISO "$ISO" doesn\'t exist
  exit 1
fi

cleanup

echo Mounting ISO
mkdir -p tmp/mount
mkdir tmp/serial
mount -t iso9660 -o loop "$ISO" tmp/mount
rsync -a tmp/mount/ tmp/serial --exclude drm_files
chmod -R u+w tmp/serial

echo Patching isolinux.cfg
sed -i "s/\(append.*\)/\1 console=${TERMINAL},${BAUD}n8/" tmp/serial/isolinux/isolinux.cfg
sed -i "1i serial 0 $BAUD" tmp/serial/isolinux/isolinux.cfg

echo Patching /etc/inittab
mkdir tmp/SA.2_working
pushd tmp/SA.2_working > /dev/null
zcat -S ".2" ../serial/isolinux/SA.2 | cpio -i --no-absolute-filenames
#edit inittab
sed -i 's/tty1::once/tty1::askfirst/' etc/inittab
echo ttyS0::once:/sbin/agetty -l /etc/rc -n -8 -L $TERMINAL $BAUD vt100 >> etc/inittab
find . | cpio --create --quiet --format='newc' | gzip -q > ../serial/isolinux/SA.2
popd

echo Making ISO image
genisoimage -r -udf -b isolinux/isolinux.bin -c isolinux/boot.catalog -o "$2" -relaxed-filenames -no-emul-boot \
  -boot-info-table -boot-load-size 4 -eltorito-alt-boot -b efiboot.img -no-emul-boot \
  -graft-points tmp/serial drm_files=tmp/mount/drm_files
