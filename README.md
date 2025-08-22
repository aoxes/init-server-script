### 一键服务器初始化脚本

此脚本旨在简化新服务器的初始配置工作，自动完成系统更新、安全加固、软件安装等步骤。

#### 脚本核心功能：

  * **自动更新系统**：执行系统更新和升级，确保服务器处于最新状态。
  * **SSH 安全加固**：
      * 随机生成新 SSH 端口（10000-65535）并自动修改配置。
      * 安装并配置 Fail2ban，自动封禁恶意 IP，增强安全性。
  * **防火墙配置**：根据系统自动配置 UFW 或 firewalld，默认只放行 SSH 新端口、HTTP (80) 和 HTTPS (443) 端口。
  * **时区自动设置**：通过 API 自动获取并设置服务器时区。
  * **Docker 一键安装**：自动安装最新版的 Docker 及其 Compose 工具。

#### 使用建议：先 DD 系统，再运行脚本

为获得纯净环境，推荐先使用 [leitbogioro](https://github.com/leitbogioro/Tools) 大佬的 DD 脚本重装系统。

**DD 系统步骤**：

1.  登录服务器，执行以下命令重装为 Debian 12。请注意，你需要将命令中的 `'your_password'` 替换为你想要设置的实际密码。
    ```bash
    wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh && bash InstallNET.sh -debian 12 -pwd 'your_password'
    ```
2.  等待系统重装并重启。

**运行初始化脚本**：

1.  系统重启后，使用新密码 SSH 登录。
2.  执行以下命令下载并运行初始化脚本：
    ```bash
    bash <(curl -s https://raw.githubusercontent.com/aoxes/init-server-script/main/init-server.sh)
    ```
3.  脚本执行完毕后会提示新 SSH 端口，请使用新端口重新连接。
