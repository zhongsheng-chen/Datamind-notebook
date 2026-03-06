#!/bin/bash
# 测试脚本

IMAGE_NAME="datamind-notebook"
TAG=${1:-latest}

echo "测试 Python 版本..."
docker run --rm ${IMAGE_NAME}:${TAG} python --version

echo "测试 Jupyter 安装..."
docker run --rm ${IMAGE_NAME}:${TAG} pip show jupyter