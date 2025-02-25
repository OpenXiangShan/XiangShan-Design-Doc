# 香山开源处理器设计文档

香山开源处理器的设计文档

## 构建

我们使用 Pandoc 和 MkDocs 来构建此文档。

### Pandoc

Pandoc 用于构建 PDF 和单页 HTML 格式的文档。

```bash
# 安装依赖
bash ./utils/dependency.sh

# 执行构建
make
```

### MkDocs

MkDocs 用来构建部署于互联网的静态网站。

```bash
# 创建并激活 Python 虚拟环境（推荐）
python3 -m venv .venv
source .venv/bin/activate

# 安装依赖
pip install -r requirements.txt

# 预览网站
mkdocs serve

# 构建网站
mkdocs build
```

## 许可协议

这份文档采用知识共享署名 4.0 协议授权。

版权所有 © 香山团队·北京开源芯片研究院
