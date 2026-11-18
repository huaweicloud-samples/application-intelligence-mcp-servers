# 贡献指南

感谢您对本项目的关注！欢迎通过以下方式贡献：

## 贡献方式

### 报告问题
如果您发现 bug 或有功能建议，请在 GitHub Issues 中创建 issue。

### 提交代码
1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/your-feature`)
3. 提交更改 (`git commit -m 'Add some feature'`)
4. 推送分支 (`git push origin feature/your-feature`)
5. 创建 Pull Request

## 开发环境设置

```bash
# 克隆仓库
git clone <repository-url>
cd application-intelligence-mcp-servers

# 安装依赖（如果需要）
pip install -r requirements.txt

# 配置华为云凭据
export HW_ACCESS_KEY="<您的Access Key>"
export HW_SECRET_KEY="<您的Secret Key>"
```

## 部署测试

参考 `README.md` 中的部署步骤进行测试。

## 代码规范

- Python 代码遵循 PEP 8
- Terraform 配置使用标准格式
- 提交前确保 `terraform validate` 通过

## 许可

通过提交代码，您同意您的贡献将基于项目许可证（MIT-0）发布。
