#!/bin/bash

mkdir -p /media/husky/HUSKYDATA

mount -t exfat \
    -o uid=husky,gid=husky,umask=0022 \
    /dev/sda1 \
    /media/husky/HUSKYDATA