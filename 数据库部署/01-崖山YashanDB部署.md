# 崖山 YashanDB 部署记录

> 版本：23.2.4.100 Personal Edition | 环境：t1 (Ubuntu)

## 一、环境准备

### 1.1 确认系统环境

```bash
# 查看系统信息
cat /etc/os-release
uname -m          # x86_64

# 查看磁盘空间
df -h /
df -h /data       # 20G 独立分区放数据
```

### 1.2 上传安装包

安装包通过 SCP 上传到 `/home/tmsxj/db-install/yashandb*.tar.gz`。

```bash
# 创建安装目录并解压
mkdir -p /home/tmsxj/yasdb_home
tar -xzf /home/tmsxj/db-install/yashandb-23.2.4.100-*.tar.gz \
  -C /home/tmsxj/yasdb_home/
```

## 二、安装部署

### 2.1 交互式安装向导

崖山使用 `yasboot init` 交互式向导完成部署：

```bash
cd /home/tmsxj/yasdb_home/yashandb/23.2.4.100/
./bin/yasboot init
```

安装向导选项：
- 模式：单机（Personal Edition 只支持单机）
- 集群名：yashandb
- 安装路径：/home/tmsxj/yasdb_home/
- 数据路径：/home/tmsxj/yasdb_data/
- 端口：1688
- 管理员密码：yasdb_123

### 2.2 加载环境变量

```bash
source /home/tmsxj/yasdb_home/yashandb/23.2.4.100/conf/yashandb.bashrc
# 或写入 ~/.bashrc
echo "source /home/tmsxj/yasdb_home/yashandb/23.2.4.100/conf/yashandb.bashrc" >> ~/.bashrc
```

### 2.3 验证安装

```bash
# 查看集群状态
yasboot cluster status -c yashandb --simple

# 期望输出：
# instance_status=open, database_role=primary
```

```bash
# 连接数据库
yasql sys/yasdb_123@192.168.1.71:1688

SQL> SELECT 1 FROM DUAL;
SQL> SELECT status FROM V$INSTANCE;
SQL> SELECT database_role FROM V$DATABASE;
```

## 三、常用管理命令

```bash
# 启动/停止集群
yasboot cluster start -c yashandb
yasboot cluster stop -c yashandb

# 查看详细状态
yasboot cluster status -c yashandb -d

# 查看日志
yasboot logs -c yashandb --tail 100
```

## 四、踩坑记录

### 4.1 环境变量未加载

**现象**：`yasboot` 或 `yasql` 命令找不到。

**解决**：每次新开 shell 需要 source 环境变量文件，建议写入 `~/.bashrc`。

### 4.2 端口被占用

**现象**：启动报错端口 1688 被占用。

**排查**：
```bash
ss -tlnp | grep 1688
lsof -i :1688
```

**解决**：停掉占用进程或修改配置文件中的端口。

> 更多通用踩坑见 [03-常见踩坑汇总](./03-常见踩坑汇总.md)
