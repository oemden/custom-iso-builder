# Manual commands Debian12 first tests

```bash
# Install required tools
sudo apt-get install xorriso isolinux

# Create working directory
mkdir debian-custom
cd debian-custom

# Download Debian netinst ISO
wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso


# Create mount point and mount the ISO
mkdir iso
sudo mount -o loop debian-12.9.0-amd64-netinst.iso iso/

# Create working directory for the new ISO
mkdir -p custom/isolinux

# Copy the content
cp -rT iso custom/

# Copy your preseed file
cp ./preseed.cfg custom/preseed.cfg

# Modify isolinux configuration
cat > custom/isolinux/txt.cfg << 'EOF'
default install
prompt 0
timeout 1
label install
        menu label ^Install
        menu default
        kernel /install.amd/vmlinuz
        append vga=788 initrd=/install.amd/initrd.gz auto=true priority=critical preseed/file=/cdrom/preseed.cfg debian-installer/language=en_US debian-installer/country=FR netcfg/dhcp_timeout=60 debconf/frontend=noninteractive console-setup/ask_detect=false
EOF

# Update MD5 sums
cd custom
find . -type f -print0 | xargs -0 md5sum > md5sum.txt
cd ..

# Create the new ISO
xorriso -as mkisofs -o debian-12.9-amd64-netinstall-auto.iso \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat \
    -b isolinux/isolinux.bin \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    custom/
```

# Or Just use preseed-creator !

```bash
Preseed Creator (c) Luc Didry 2017, GNU GPLv3
preseed-creator [options]
    Options:
        -i <image.iso>              ISO image to preseed. If not provided, the script will download and use the latest Debian amd64 netinst ISO image
        -o <preseeded_image.iso>    output preseeded ISO image. Default to debian-preseed.iso
        -p <preseed_file.cfg>       preseed file. If not provided, the script will put "d-i debian-installer/locale string fr_FR" in the preseed.cfg file
        -w <directory>              directory used to work on ISO image files. Default is a temporary folder in /tmp
        -t <int>                    timeout before the installer starts.
                                    0 disables the timeout, the installer will not start itself, you’ll need to start it manually.
                                    Default is 0
        -x                          Use xorriso instead of genisoimage, to create an iso-hybrid
        -d                          download the latest Debian amd64 netinst ISO image in the current folder and exit
        -g                          download the latest Debian stable example preseed file into preseed_example.cfg and exit
        -v                          activate verbose mode
        -h                          print this help and exit
```

```bash
wget https://framagit.org/fiat-tux/hat-softwares/preseed-creator/-/raw/main/preseed-creator
chmod +x preseed-creator
sudo preseed-creator -i ./debian-12.9.0-amd64-netinst.iso -o ./debian-12.9-amd64-netinstall-auto-4.iso -p ./preseed.cfg -x -t 3  -w ./iso -v
```
