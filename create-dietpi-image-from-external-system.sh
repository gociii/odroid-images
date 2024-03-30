#!/bin/bash

# run as root: sudo su

apt install btrfs-progs -y;

DEV_GITBRANCH=master
DEV_GITOWNER=MichaIng
bash -c "$(curl -sSf https://raw.githubusercontent.com/MichaIng/DietPi/master/.build/images/dietpi-imager)"
