# datamind-notebook

克隆 Datamind 计算环境的 Jupyter Notebook 镜像，基于 Python 3.10-slim。

## ✨ 特性

- 🐍 Python 3.10 精简版基础镜像
- 📓 预装 Jupyter Notebook 和 JupyterLab
- 📦 常用数据科学库（numpy, pandas, matplotlib, scikit-learn 等）
- 🔧 智能入口脚本，支持多种命令和配置
- 💾 自动 Token 管理
- 🩺 健康检查支持

## 🚀 快速开始

### 1. 构建镜像
```bash
make build
# 或
docker build -t datamind-notebook:latest .