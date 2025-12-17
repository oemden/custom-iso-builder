# Custom-iso

## Project Overview
This repository contains a script to automate the creation of Custom-iso for Debian.
Intended to be used with WMWare but should work with any hypervisor or on USB.

### TODOs


- fetch from hypervisor if md5checksum is Correct.
- if not remove uploaded iso ( add option )
- add option OVERRIDE_EXISTING_CUSTOM_ISO={true,false}
- do varaible substitution for the preseed file
- create a dockerfile / docker-compose to automate ISO creation on demand with GitOps

## Main Contributor
oem <oem@mobiloem>
