# TODOS

- [ ] TODO: variable substitutions in preseed file (LATER USE)
- [ ] export PRESEED_NETCFG_HOSTNAME PRESEED_NETCFG_DOMAIN
- [ ] envsubst < ${install_config_template_path} > ${install_config_file_path}
- [ ] Verify ISO checksum (LATER USE)
- [ ] wget ${iso_checksum} -O SHA256SUMS
- [ ] grep "${debian_iso_name}" SHA256SUMS | sha256sum -c -
- [ ] todo: detect if isolinux exists for older versions
- [ ] - Create remote directory on ssh host if it doesn't exist (LATER USE)
- [ ] - Loading bar for ssh upload (LATER USE)
- [ ] - Parallel ssh upload (LATER USE)
- [ ] - Check if remote ISO file exists on ssh host
- [ ] - Upload to temp directory on ssh host
- [ ] Verify checksum on remote host (LATER USE)

## Cheksum Option

- [ ] Generate SHA256 checksum = true|false # speedUp process until md5 can be checked on ESXi host itself to validate Upload

## Ubuntu autoinstall check tool

- [ ] Use subiquity check tools to validate autoinstall file ( potentially requires UBUNTU based Docker but should work on Debian from Scratch )
- [ ] find preseed validation tools

## cloud-init Check-tool

## Windows Support

Add .ISO Windows Support with autounattended.xml

Sources:

- [https://github.com/memstechtips/UnattendedWinstall](https://github.com/memstechtips/UnattendedWinstall)
- [https://github.com/cschneegans/unattend-generator](https://github.com/cschneegans/unattend-generator)
- [https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11)
- [https://forum.proxmox.com/threads/fully-unattended-windows-11-installation-avoid-press-any-key-to-boot-from-cd-or-dvd.162252/post-754419](https://forum.proxmox.com/threads/fully-unattended-windows-11-installation-avoid-press-any-key-to-boot-from-cd-or-dvd.162252/post-754419)
- [https://blog.linux-ng.de/2025/01/02/build-unattended-windows-iso/](https://blog.linux-ng.de/2025/01/02/build-unattended-windows-iso/)

## Rocky .ISO

- [ ] Explore Rocky Linux ISO ( almost certainly requires Rocky based Docker file )
