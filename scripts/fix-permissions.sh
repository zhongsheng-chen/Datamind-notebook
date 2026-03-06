#!/bin/bash
# Set permissions on a directory
# After any installation, if a directory needs to be (human) user-writable, run this script on it.
# It will make everything in the directory owned by the group ${NB_GID} and writable by that group.
# Deployments that want to set a specific user id can preserve permissions
# by adding the `--group-add users` line to `docker run`.

# Uses find to avoid touching files that already have the right permissions,
# which would cause a massive image explosion

# Right permissions are:
# group=${NB_GID}
# AND permissions include group rwX (directory-execute)
# AND directories have setuid,setgid bits set

set -e

# 如果没有提供参数或请求帮助，显示用法
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 <directory> [<directory> ...]"
    echo "Fix permissions for directories to be group-writable by NB_GID (${NB_GID:-1000})"
    exit 0
fi

# 如果未设置 NB_GID，默认使用 1000
NB_GID="${NB_GID:-1000}"

for d in "$@"; do
    if [ -d "${d}" ]; then
        echo "Fixing permissions on: ${d} (group: ${NB_GID})"
        
        # 修复文件和目录的所有权和权限
        find "${d}" \
            ! \( \
                -group "${NB_GID}" \
                -a -perm -g+rwX \
            \) \
            -exec chgrp "${NB_GID}" -- {} \+ \
            -exec chmod g+rwX -- {} \+
        
        # 专门为目录设置 setuid 和 setgid 位
        find "${d}" \
            \( \
                -type d \
                -a ! -perm -6000 \
            \) \
            -exec chmod +6000 -- {} \+
        
        echo "✓ Permissions fixed on: ${d}"
    else
        echo "Warning: Directory does not exist: ${d}"
    fi
done