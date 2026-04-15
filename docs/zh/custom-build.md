# Custom Build 使用说明

[返回 README](../../README.md) | 中文 | [English](../en/custom-build.md)

如果你只是想 **快速做出一份自己的镜像**，最推荐的方式就是用 GitHub Actions 里的 **Custom Build**。

你可以把它理解成：

> 不用自己配本地构建环境，直接在网页上填几个参数，然后等 GitHub 帮你把镜像做好。

通常情况下：

- 只跑构建时，大约需要 **5 分钟左右**
- 如果包含测试，通常需要 **10 分钟左右**

如果你只是想先**快速体验 Landscape**，不急着改参数，推荐直接去仓库的 **Release** 页面下载我们已经预编译好的镜像，这会更快。

---

## 3 分钟快速上手

如果你是第一次用，直接按下面做就行。

### 第一步：打开 Actions

进入你自己的 fork 仓库后：

- 点击顶部 **Actions**
- 在左侧找到 **Custom Build**
- 点击 **Run workflow**

---

### 第二步：选一个 variant

如果你不确定选哪个，先用：

- `default`

常见选择可以这样理解：

- `default`：最通用，推荐第一次先用它
- `docker`：镜像里会带 Docker
- `alpine`：更轻量
- `alpine-docker`：轻量 + Docker

如果你只是想先成功构建一版，**直接选 `default`**。

---

### 第三步：按需填写参数

最常见的情况是两种。

#### 情况 A：只改网络

如果你只是想改 LAN / DHCP 参数，可以填：

- `lan_server_ip=192.168.50.1`
- `lan_range_start=192.168.50.100`
- `lan_range_end=192.168.50.200`
- `lan_netmask=24`

这些参数分别可以这样理解：

- `lan_server_ip`
  - 路由器在 LAN 里的地址
  - 一般也会作为网关 / DHCP 服务地址
  - 常见写法：`192.168.50.1`

- `lan_range_start`
  - DHCP 自动分配的起始地址
  - 常见写法：`192.168.50.100`

- `lan_range_end`
  - DHCP 自动分配的结束地址
  - 常见写法：`192.168.50.200`

- `lan_netmask`
  - 子网前缀长度
  - 大多数情况直接用 `24`

填写时注意：

- `lan_server_ip` 不要和 DHCP 地址池重复
- `lan_range_start` / `lan_range_end` 要在同一网段里
- 如果你不懂子网，通常直接填 `24` 就够了

其他保持默认或留空即可。

#### 情况 B：同时改密码

如果你还想顺便改登录密码和 Web 管理账号，可以再填：

- `root_password=Passw0rd!234`
- `api_username=admin`
- `api_password=Adm1n!234`

这些参数分别是：

- `root_password`
  - Linux 系统登录密码
  - 会影响：
    - `root`
    - `ld`

- `api_username`
  - Web 管理用户名

- `api_password`
  - Web 管理密码

如果你只是个人使用、临时测试，直接填也可以。

如果你比较在意安全，建议把这些值放到 GitHub Secrets 里，而不是直接填在输入框中。

#### 其他常见输入

- `landscape_version`
  - 指定要使用的 Landscape 版本
  - 留空时使用仓库默认值
  - 如果你不确定，通常直接留空

当前优先级是：

**direct inputs > secrets > defaults**

也就是说：

- 你手动填了输入框，就优先用输入框
- 没填，才会尝试读取 GitHub Secrets
- Secrets 也没有，才回退到默认值

---

### 第四步：点击运行

填完后点击：

- **Run workflow**

然后等待 GitHub Actions 开始执行。

---

### 第五步：下载构建结果

等 workflow 跑完后：

- 打开这次运行记录
- 在页面下方找到 **Artifacts**
- 下载对应的构建产物

你拿到的通常会包含：

- 镜像文件 `.img`
- 构建元信息 `build-metadata.txt`
- 生效配置 `effective-landscape_init.toml`

如果你只是想拿镜像用，重点看 `.img` 就可以。

---

## Tips

- 如果你只是想先确认镜像能不能构建出来，不一定要等完整测试全部结束。
- 只要本次运行里对应的镜像 artifact 已经上传完成，你就可以先下载试用。
- 如果你只是想快速体验，不改参数的话，通常直接去 **Release** 页面下载预编译镜像更省事。
- 第一次使用时，最稳妥的选择仍然是：`variant=default`，其余只改你真正关心的参数。
- 如果你准备长期使用，或者比较在意安全，建议把密码放到 GitHub Secrets 里。

---

## 什么时候用 Custom Build，什么时候不用

### 推荐用 Custom Build

如果你符合下面这些情况，优先推荐使用 Custom Build：

- 你 fork 了这个仓库，想生成自己的镜像
- 你不想折腾本地 Linux 构建环境
- 你希望直接在网页上点几下就完成构建
- 你只想改一些常用参数，而不是改代码

### 更适合本地构建

如果你是下面这些情况，本地更合适：

- 你在修改 `build.sh`、`lib/`、`rootfs/`、测试脚本
- 你在开发 workflow 本身
- 你需要频繁调试
- 你要验证还没推送到 GitHub 的本地代码

简单说：

- **想生成镜像** → 优先 Custom Build
- **想开发构建系统本身** → 本地构建

---

## 密码怎么处理更合适

这里给一个最简单的判断方式。

### 如果你只是自己临时用
可以直接填输入框。

### 如果你准备长期使用，或者比较在意安全
建议改用 GitHub Secrets。

---

## 构建完成后还能做什么

如果你已经成功跑完一次 Custom Build，后面还可以继续用：

- **Test Image**

它适合做这些事：

- 对已有 artifact 再跑一次复测
- 补做 readiness / dataplane 验证
- 重新传 SSH / API 凭据测试

你可以把它理解成：

> Custom Build 负责“生成镜像”，Test Image 负责“再检查一次镜像”。

---

## 常见问题

### 我第一次到底选哪个 variant？

直接选：

- `default`

### `landscape_version` 我看不懂，要不要填？

一般不用填，留空即可。

### 我只想改 LAN 网段，其他不动，可以吗？

可以，直接只填网络相关参数即可。

### 我一定要用 Secrets 吗？

不一定。

个人 fork、临时测试，或者更看重方便时，直接在输入框里填写也可以。

如果你更在意安全，再考虑用 Secrets。

### 我跑完后去哪里拿镜像？

去这次 workflow 的运行页面，在 **Artifacts** 里下载。

---

## 一句话建议

如果你的目标是：

> **“我想尽快做出一份自己的镜像。”**

那就先用 **Custom Build**，不要先从本地构建开始。

先把镜像做出来，再决定要不要继续折腾更复杂的自定义。