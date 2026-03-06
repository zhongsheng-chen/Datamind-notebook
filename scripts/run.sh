#!/bin/bash
# 运行脚本

IMAGE_NAME="datamind-notebook"
TAG=${1:-latest}
PORT=${2:-8888}

echo "启动容器..."
docker run -it --rm \
    -p ${PORT}:8888 \
    -v $(pwd)/..:/workspace \
    ${IMAGE_NAME}:${TAG}