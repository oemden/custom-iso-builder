#!/bin/bash
# v0.1.0
# This script creates a customized Debian ISO with a preseed file for automated installation.
# iso creation based on preseed-creator tool: https://framagit.org/fiat-tux/hat-softwares/preseed-creator/

dirpath=$(pwd)

# source config variables
source ./.env
source ${dirpath}/config/debian13.1.0.cfg
if [ $? -ne 0 ]; then
  echo "Failed to source config file!"
  exit 1
fi

# # Generate preseed file from template
# TODO: variable substitutions in preseed file
# Using envsubst for variable substitution in preseed file
# for now we copy the template directly
if [[ ! -f "${dirpath}/${preseed_dirname}/${preseed_template}" ]] && [[ ! -f "${dirpath}/${preseed_dirname}/${preseed_file}" ]]; then
  echo "preseed file ${dirpath}/${preseed_dirname}/${preseed_file} or template ${dirpath}/${preseed_dirname}/${preseed_template} not found! Aboting."
  exit 1
elif [[ -f "${dirpath}/${preseed_dirname}/${preseed_template}" ]] && [[ ! -f "${dirpath}/${preseed_dirname}/${preseed_file}" ]]; then
  echo "No preseed file found, copying template ${dirpath}/${preseed_dirname}/${preseed_template} to ${dirpath}/${preseed_dirname}/${preseed_file}"
  cp ${dirpath}/${preseed_dirname}/${preseed_template} ${dirpath}/${preseed_dirname}/${preseed_file}
fi

# substituion: LATER USE
# export PRESEED_NETCFG_HOSTNAME PRESEED_NETCFG_DOMAIN
# envsubst < ./${preseed_dirname}/preseed_debian13_template.cfg > ./${preseed_dirname}/${preseed_file}
# if [ $? -ne 0 ]; then
#   echo "Failed to generate preseed file from template!"
#   exit 1
# fi

# ## Install required tools
# TODO ramove sudo and check for sudo
sudo apt-get install xorriso isolinux

# # install preseed-creator
# wget --quiet --content-disposition   "https://cloud.fiat-tux.fr/s/debian-packages/download?path=%2Fpreseed-creator&files=preseed-creator_0.05.deb"   "https://cloud.fiat-tux.fr/s/debian-packages/download?path=%2Fpreseed-creator&files=preseed-creator_0.05.deb.minisig" &&   minisign -Vm preseed-creator_0.05.deb -P RWQm7sZSguNVtitOiU4ozG+HgWWyUz4KmB0NMhjuTYkMardZlXjsKWLk &&   sudo apt install ./preseed-creator_0.05.deb

# check if preseed-creator is installed
if command -v preseed-creator -h &> /dev/null
then
    echo "preseed-creator is already installed"
    preseed-creator -h
    else
    echo "preseed-creator could not be found, installing..."
    wget https://framagit.org/fiat-tux/hat-softwares/preseed-creator/-/raw/main/preseed-creator
    chmod +x preseed-creator
    if [[ -f ./preseed-creator ]]; then
      echo "preseed-creator downloaded successfully"
    else
      echo "Failed to download preseed-creator!"
      exit 1
    fi
    # move to /usr/local/bin
    sudo mv ${dirpath}/preseed-creator /usr/local/bin/
    echo
    preseed-creator -h
fi

# Download Debian netinst ISO
echo "Downloading Debian ISO version ${debian_version} from ${iso_url} ..."
mkdir -p ${dirpath}/${iso_directory}
# Check if iso exists
if [ -f "${dirpath}/${iso_directory}/${debian_iso_name}" ]; then
    if [[ ${OVERRIDE_EXISTING_SOURCE_ISO} = true ]]; then
        echo "Debian ISO already exists at ${iso_directory}/${debian_iso_name}, but OVERRIDE_EXISTING_SOURCE_ISO is set to true, re-downloading..."
        rm -f ${dirpath}/${iso_directory}/${debian_iso_name}
        wget ${iso_url} -O ${dirpath}/${iso_directory}/${debian_iso_name}
    else
        echo "Debian ISO already exists at ${iso_directory}/${debian_iso_name}, skipping download."
    fi
else
  echo "Debian ISO not found, downloading..."
  wget ${iso_url} -O ${dirpath}/${iso_directory}/${debian_iso_name}
  if [ $? -ne 0 ]; then
    echo "Failed to download Debian ISO!"
    exit 1
  fi
fi

# Verify ISO checksum
# echo "Verifying ISO checksum..."
# wget ${iso_checksum} -O SHA256SUMS
# grep "${iso_directory}/${iso_volume_name}" SHA256SUMS | sha256sum -c -  || { echo "Checksum verification failed!"; exit 1; }    
# if [ $? -ne 0 ]; then
#   echo "Checksum verification failed!"
#   exit 1
# else
#   echo "Checksum verification passed."
# fi

# Create customized ISO with preseed file
echo "Creating the customized ISO..."
mkdir -p ${dirpath}${working_directory}
# check if destination iso exist
if [[ -f ${dirpath}/${iso_directory}/${custom_iso_name} ]]; then
  echo "Customized ISO ${custom_iso_name} already exists in ${iso_directory}, renaming it first."
  mv ${dirpath}/${iso_directory}/${custom_iso_name} ${dirpath}/${iso_directory}/${custom_iso_name}.old
fi

# sudo preseed-creator -i ./${iso_directory}/${debian_iso_name} -o ./${iso_directory}/${custom_iso_name} -p ./${preseed_dirname}/${preseed_file} -x -t 3  -v -w ${working_directory}
sudo preseed-creator -i ${dirpath}/${iso_directory}/${debian_iso_name} -o ${dirpath}/${iso_directory}/${custom_iso_name} -p ${dirpath}/${preseed_dirname}/${preseed_file} -x -t 3 -w ${dirpath}${working_directory} -v 
if [ $? -ne 0 ]; then
  echo "Failed to create customized ISO!"
  exit 1
fi

# Generate md5 checksum file of our custom .iso
echo "Generating md5 checksum of the customized ISO..."
custom_iso_checksum=$(sha256sum ${dirpath}/${iso_directory}/${custom_iso_name} | awk '{print $1}')
custom_iso_checksum_local=${dirpath}/${iso_directory}/${custom_iso_name}.md5
echo "${custom_iso_checksum}" > ${custom_iso_checksum_local}

################### Upload to Hypervisor or cloud platform #######################
# TODO implement upload to cloud platform, eg: proxmox, aws, ... For Now dirty scp to (ESXI) hypervisor
# echo "Uploading customized ISO to hypervisor..."

echo "Uploading customized ISO to VMware ESXi host ${VMWARE_SSH_HOST_CONFIG} ..."
# Upload md5 checksum of the custom .iso file
scp ${custom_iso_checksum_local} ${VMWARE_SSH_HOST_CONFIG}:${VMWARE_ISO_UPLOAD_PATH}/

# Upload the custom .iso file
scp ${dirpath}/${iso_directory}/${custom_iso_name} ${VMWARE_SSH_HOST_CONFIG}:${VMWARE_ISO_UPLOAD_PATH}/

# Compare checksum on remote host
# # later - need to find simple way to do this with ssh
# echo "Verifying uploaded ISO checksum on VMware ESXi host ${VMWARE_SSH_HOST_CONFIG}"
# ssh ${VMWARE_SSH_HOST_CONFIG} "
#   custom_iso_checksum_remote=$(cat ${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name}.md5)
#   custom_iso_checksum=$(sha256sum ${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name} | awk '{print $1}')
#   if [[ "${custom_iso_checksum_remote}" == "${custom_iso_checksum}" ]]; then
#     echo "Customized ISO checksum matches the original."
#   else
#     echo "Warning: Customized ISO checksum does not match the original!"
#   fi
# "

if [ $? -ne 0 ]; then
  echo "Failed to upload customized ISO to VMware ESXi host!"
  exit 1
fi 
# echo "Customized ISO uploaded successfully to VMware ESXi host ${VMWARE_SSH_HOST_CONFIG} at path ${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name}"


# # delete the iso directory
if [[ -d ${dirpath}${working_directory} ]]; then
    echo "Cleaning up working directory ${dirpath}${working_directory} ..."
    rmdir ${dirpath}${working_directory}
else
    echo "Working directory ${dirpath}${working_directory} not found, skipping cleanup."
fi

echo "Customized ISO created successfully at ${dirpath}/${iso_directory}/${custom_iso_name} and uploaded to VMware ESXi host ${VMWARE_SSH_HOST_CONFIG} at path ${VMWARE_ISO_UPLOAD_PATH}/${custom_iso_name}"
exit 0

# End of script
