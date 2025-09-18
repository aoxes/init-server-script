# **一键服务器初始化脚本**

此脚本旨在简化新服务器的初始配置过程，通过自动化执行系统更新、安全加固和软件安装等步骤，为您提供一个安全且纯净的基础环境。

## **主要功能**

  * **系统安全加固**
      * **SSH 端口修改**：可随机生成一个新 SSH 端口（10000-65535），并自动修改配置。用户也可通过 `-p` 或 `--port` 参数指定端口。
      * **Fail2ban 配置**：自动安装并配置 Fail2ban，对恶意登录尝试的 IP 进行**永久封禁**，显著增强服务器安全性。
  * **防火墙自动配置**
      * 脚本可根据您的系统（如 Ubuntu、Debian 等）自动安装并配置 UFW 或 firewalld。
      * 默认只开放新的 SSH 端口、HTTP (80) 和 HTTPS (443) 端口，确保网络安全。
  * **自动设置时区**
      * 通过 API 自动获取并设置服务器时区，无需手动操作。
  * **可选安装 Docker**
      * 新增 `--add docker` 参数，可选择性地一键安装最新版的 Docker 及其 Compose 工具，使脚本更加灵活。

## **使用建议**

为确保环境纯净，推荐您先使用 DD 脚本重装系统，例如来自 **leitbogioro** 的脚本。

**DD 系统步骤：**

1.  登录服务器并执行以下命令，将系统重装为 Debian 12。请将 `'your_password'` 替换为您想要设置的实际密码。
    ```bash
    wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh && bash InstallNET.sh -debian 12 -pwd 'your_password'
    ```
2.  等待系统重装并重启。

## **运行初始化脚本**

1.  系统重启后，使用您设置的新密码通过 SSH 登录。
2.  执行以下命令以下载并运行初始化脚本。
      * **基础运行**：
        ```bash
        bash <(curl -s https://raw.githubusercontent.com/aoxes/init-server-script/main/init-server.sh)
        ```
      * **自定义端口**：将 `post` 替换为您想要的端口号。
        ```bash
        bash <(curl -s https://raw.githubusercontent.com/aoxes/init-server-script/main/init-server.sh) -p post
        ```
      * **安装 Docker**：
        ```bash
        bash <(curl -s https://raw.githubusercontent.com/aoxes/init-server-script/main/init-server.sh) --add docker
        ```
3.  脚本执行完毕后会提示新的 SSH 端口号。您需要使用该新端口重新连接服务器。

**注意**：该脚本目前主要在 Debain 12 环境下进行过充分测试，在其他系统上请酌情使用。
