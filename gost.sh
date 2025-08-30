#!/bin/bash

# Gost 管理脚本
# 支持 TCP+UDP 双协议端口转发
# 版本: v1.0.1 - 优化版（添加快捷方式和时间显示）

CONFIG_FILE="/etc/gost/config.yaml"
SERVICE_FILE="/etc/systemd/system/gost.service"
BINARY_PATH="/usr/local/bin/gost"
CONFIG_BACKUP_DIR="/etc/gost/backups"
RAW_CONF_PATH="/etc/gost/rawconf"
REMARKS_PATH="/etc/gost/remarks.txt"
EXPIRES_PATH="/etc/gost/expires.txt"
TRAFFIC_PATH="/etc/gost/traffic.db"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示当前时间
show_time() {
    echo -e "${YELLOW}当前时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
}

# 检查 root 权限
check_root() {
    [[ $EUID != 0 ]] && echo -e "${RED}错误: 需要root权限运行此脚本${NC}" && exit 1
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}错误: 未找到 $1 命令${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}安装系统依赖...${NC}"
    if command -v apt &> /dev/null; then
        apt update
        apt install -y wget tar curl jq ufw bc
    elif command -v yum &> /dev/null; then
        yum install -y wget tar curl jq bc
    elif command -v dnf &> /dev/null; then
        dnf install -y wget tar curl jq bc
    else
        echo -e "${RED}不支持的包管理器${NC}"
        exit 1
    fi
}

# 下载并安装 Gost
install_gost() {
    echo -e "${YELLOW}开始安装 Gost...${NC}"
    
    # 创建配置目录
    mkdir -p /etc/gost
    mkdir -p $CONFIG_BACKUP_DIR

    # 下载 Gost
    cd /tmp
    wget -q --show-progress https://github.com/go-gost/gost/releases/download/v3.2.4/gost_3.2.4_linux_amd64.tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载 Gost 失败${NC}"
        exit 1
    fi

    # 解压并安装
    tar -xzf gost_3.2.4_linux_amd64.tar.gz
    cp gost /usr/local/bin/
    chmod +x /usr/local/bin/gost

    # 创建默认配置
    create_default_config

    # 创建系统服务
    create_systemd_service

    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable gost
    systemctl start gost

    # 创建流量监控脚本
    create_traffic_scripts

    # 创建快捷方式
    create_shortcut

    echo -e "${GREEN}Gost 安装完成!${NC}"
    echo -e "${YELLOW}请使用配置菜单设置转发规则${NC}"
}

# 创建快捷方式
create_shortcut() {
    echo -e "${YELLOW}创建快捷命令...${NC}"
    
    # 复制脚本到系统路径
    cp "$0" /usr/local/bin/gost-manager.sh
    chmod +x /usr/local/bin/gost-manager.sh
    
    # 创建软链接
    ln -sf /usr/local/bin/gost-manager.sh /usr/bin/g
    
    echo -e "${GREEN}快捷命令 'g' 创建成功!${NC}"
    echo -e "${YELLOW}现在可以使用 'g' 命令快速打开管理面板${NC}"
}

# 创建默认配置 (使用 YAML 格式)
create_default_config() {
    cat > $CONFIG_FILE << 'EOF'
# Gost 端口转发配置
# 用于转发 Reality 和 Shadowsocks 流量

services: []
EOF
    
    # 初始化其他配置文件
    touch $RAW_CONF_PATH $REMARKS_PATH $EXPIRES_PATH $TRAFFIC_PATH
}

# 创建系统服务
create_systemd_service() {
    cat > $SERVICE_FILE << EOF
[Unit]
Description=Gost Proxy Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=$BINARY_PATH -C $CONFIG_FILE
Restart=always
RestartSec=5
LimitNOFILE=65536
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=gost

[Install]
WantedBy=multi-user.target
EOF
}

# 创建流量监控脚本
create_traffic_scripts() {
    # 到期检查脚本
    cat > /usr/local/bin/gost-expire-check.sh << 'EOF'
#!/bin/bash
EXPIRES_FILE="/etc/gost/expires.txt"
RAW_CONF="/etc/gost/rawconf"
GOST_CONF="/etc/gost/config.yaml"

[ ! -f "$EXPIRES_FILE" ] && exit 0

current_time=$(date +%s)
expired_ports=""
need_rebuild=false

while IFS=: read -r port expire_date; do
    if [ "$expire_date" != "永久" ] && [ "$expire_date" -le "$current_time" ]; then
        expired_ports="$expired_ports $port"
        need_rebuild=true
    fi
done < "$EXPIRES_FILE"

if [ "$need_rebuild" = true ]; then
    for port in $expired_ports; do
        sed -i "/:${port}#/d" "$RAW_CONF"
        sed -i "/^${port}:/d" "$EXPIRES_FILE"
        sed -i "/^${port}:/d" "/etc/gost/remarks.txt"
        echo "[$(date)] 端口 $port 的转发规则已过期并删除" >> /var/log/gost.log
    done
    rebuild_config
    systemctl restart gost >/dev/null 2>&1
fi
EOF

    # 流量监控脚本
    cat > /usr/local/bin/gost-traffic-monitor.sh << 'EOF'
#!/bin/bash
TRAFFIC_DB="/etc/gost/traffic.db"
RAW_CONF="/etc/gost/rawconf"

[ ! -f "$RAW_CONF" ] && exit 0

touch "$TRAFFIC_DB"

while IFS= read -r line; do
    port=$(echo "$line" | cut -d':' -f2 | cut -d'#' -f1)
    total_bytes=0
    
    # 获取端口的流量统计（这里需要根据实际监控方式实现）
    # 这只是一个示例，实际需要根据你的监控系统来获取流量数据
    
    old_data=$(grep "^$port:" "$TRAFFIC_DB" 2>/dev/null)
    if [ -n "$old_data" ]; then
        old_total=$(echo "$old_data" | cut -d: -f2)
        new_total=$((old_total + total_bytes))
        sed -i "/^$port:/d" "$TRAFFIC_DB"
        echo "$port:$new_total" >> "$TRAFFIC_DB"
    else
        echo "$port:$total_bytes" >> "$TRAFFIC_DB"
    fi
done < "$RAW_CONF"
EOF

    chmod +x /usr/local/bin/gost-expire-check.sh
    chmod +x /usr/local/bin/gost-traffic-monitor.sh

    # 添加定时任务
    echo "0 * * * * root /usr/local/bin/gost-expire-check.sh >/dev/null 2>&1" > /etc/cron.d/gost-expire
    echo "*/5 * * * * root /usr/local/bin/gost-traffic-monitor.sh >/dev/null 2>&1" >> /etc/cron.d/gost-expire
}

# 备份配置
backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$CONFIG_BACKUP_DIR/config_$timestamp.yaml"
    cp $RAW_CONF_PATH "$CONFIG_BACKUP_DIR/rawconf_$timestamp"
    cp $REMARKS_PATH "$CONFIG_BACKUP_DIR/remarks_$timestamp.txt"
    cp $EXPIRES_PATH "$CONFIG_BACKUP_DIR/expires_$timestamp.txt"
    echo -e "${GREEN}配置已备份到: $CONFIG_BACKUP_DIR/${NC}"
}

# 导入备份配置
import_config() {
    echo -e "${YELLOW}可用备份文件:${NC}"
    local backups=($(ls -1 $CONFIG_BACKUP_DIR/*.yaml 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${RED}没有找到备份文件${NC}"
        return 1
    fi

    for i in "${!backups[@]}"; do
        echo "$((i+1)). ${backups[$i]}"
    done

    read -p "请选择要恢复的备份文件编号: " choice
    if [[ $choice -ge 1 && $choice -le ${#backups[@]} ]]; then
        local selected_file="${backups[$((choice-1))]}"
        local base_name=$(basename "$selected_file" .yaml | sed 's/config_//')
        
        cp "$selected_file" $CONFIG_FILE
        cp "$CONFIG_BACKUP_DIR/rawconf_$base_name" $RAW_CONF_PATH 2>/dev/null
        cp "$CONFIG_BACKUP_DIR/remarks_$base_name.txt" $REMARKS_PATH 2>/dev/null
        cp "$CONFIG_BACKUP_DIR/expires_$base_name.txt" $EXPIRES_PATH 2>/dev/null
        
        systemctl restart gost
        echo -e "${GREEN}配置已从备份恢复${NC}"
    else
        echo -e "${RED}无效的选择${NC}"
    fi
}

# 更新 Gost
update_gost() {
    echo -e "${YELLOW}开始更新 Gost...${NC}"
    
    # 备份当前配置
    backup_config

    # 停止服务
    systemctl stop gost

    # 下载新版本
    cd /tmp
    wget -q --show-progress https://github.com/go-gost/gost/releases/download/v3.2.4/gost_3.2.4_linux_amd64.tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}下载 Gost 失败${NC}"
        exit 1
    fi

    # 解压并更新
    tar -xzf gost_3.2.4_linux_amd64.tar.gz
    cp gost /usr/local/bin/
    chmod +x /usr/local/bin/gost

    # 启动服务
    systemctl start gost

    echo -e "${GREEN}Gost 更新完成!${NC}"
}

# 卸载 Gost
uninstall_gost() {
    echo -e "${YELLOW}开始卸载 Gost...${NC}"
    
    # 停止服务
    systemctl stop gost
    systemctl disable gost

    # 删除文件
    rm -f $BINARY_PATH
    rm -f $SERVICE_FILE
    rm -rf /etc/gost
    rm -f /usr/local/bin/gost-expire-check.sh
    rm -f /usr/local/bin/gost-traffic-monitor.sh
    rm -f /etc/cron.d/gost-expire
    rm -f /usr/local/bin/gost-manager.sh
    rm -f /usr/bin/g

    # 重载系统服务
    systemctl daemon-reload

    echo -e "${GREEN}Gost 已卸载!${NC}"
}

# 服务管理
service_management() {
    while true; do
        echo -e "${CYAN}=== 服务管理 ===${NC}"
        echo -e "1. 启动 Gost"
        echo -e "2. 停止 Gost"
        echo -e "3. 重启 Gost"
        echo -e "4. 查看服务状态"
        echo -e "5. 查看服务日志"
        echo -e "6. 启用开机自启"
        echo -e "7. 禁用开机自启"
        echo -e "00. 返回主菜单"
        echo -e "${CYAN}================${NC}"
        
        read -p "请选择操作 [1-7, 00]: " choice
        case $choice in
            1)
                systemctl start gost
                echo -e "${GREEN}Gost 已启动${NC}"
                ;;
            2)
                systemctl stop gost
                echo -e "${YELLOW}Gost 已停止${NC}"
                ;;
            3)
                systemctl restart gost
                echo -e "${GREEN}Gost 已重启${NC}"
                ;;
            4)
                systemctl status gost --no-pager -l
                ;;
            5)
                journalctl -u gost -n 50 --no-pager
                ;;
            6)
                systemctl enable gost
                echo -e "${GREEN}已启用开机自启${NC}"
                ;;
            7)
                systemctl disable gost
                echo -e "${YELLOW}已禁用开机自启${NC}"
                ;;
            00)
                return
                ;;
            *)
                echo -e "${RED}无效选择!${NC}"
                ;;
        esac
    done
}

# 重建配置（关键修复）
rebuild_config() {
    if [ ! -f "$RAW_CONF_PATH" ] || [ ! -s "$RAW_CONF_PATH" ]; then
        echo '# Gost 端口转发配置' > $CONFIG_FILE
        echo 'services: []' >> $CONFIG_FILE
    else
        # 使用正确的YAML格式
        echo '# Gost 端口转发配置' > $CONFIG_FILE
        echo 'services:' >> $CONFIG_FILE
        
        while IFS= read -r line; do
            local_port=$(echo "$line" | cut -d':' -f2 | cut -d'#' -f1)
            target=$(echo "$line" | cut -d'#' -f2)
            target_port=$(echo "$line" | cut -d'#' -f3)
            
            # 添加TCP转发
            echo "  - name: forward-${local_port}-tcp" >> $CONFIG_FILE
            echo "    addr: :${local_port}" >> $CONFIG_FILE
            echo "    handler:" >> $CONFIG_FILE
            echo "      type: tcp" >> $CONFIG_FILE
            echo "    listener:" >> $CONFIG_FILE
            echo "      type: tcp" >> $CONFIG_FILE
            echo "    forwarder:" >> $CONFIG_FILE
            echo "      nodes:" >> $CONFIG_FILE
            echo "        - name: target-tcp" >> $CONFIG_FILE
            echo "          addr: ${target}:${target_port}" >> $CONFIG_FILE
            echo "" >> $CONFIG_FILE
            
            # 添加UDP转发
            echo "  - name: forward-${local_port}-udp" >> $CONFIG_FILE
            echo "    addr: :${local_port}" >> $CONFIG_FILE
            echo "    handler:" >> $CONFIG_FILE
            echo "      type: udp" >> $CONFIG_FILE
            echo "    listener:" >> $CONFIG_FILE
            echo "      type: udp" >> $CONFIG_FILE
            echo "    forwarder:" >> $CONFIG_FILE
            echo "      nodes:" >> $CONFIG_FILE
            echo "        - name: target-udp" >> $CONFIG_FILE
            echo "          addr: ${target}:${target_port}" >> $CONFIG_FILE
            echo "" >> $CONFIG_FILE
            
        done < "$RAW_CONF_PATH"
    fi
}

# 添加 TCP+UDP 双协议转发
add_dual_forward() {
    read -p "请输入本地监听端口: " local_port
    read -p "请输入目标地址: " target
    read -p "请输入目标端口: " target_port
    read -p "请输入规则名称: " name

    if [[ -z "$name" ]]; then
        name="forward-$local_port"
    fi

    if [[ ! $local_port =~ ^[0-9]+$ ]] || [[ ! $target_port =~ ^[0-9]+$ ]]; then
        echo -e "${RED}端口必须为数字${NC}"
        sleep 2
        return
    fi

    if grep -q ":${local_port}#" "$RAW_CONF_PATH" 2>/dev/null; then
        echo -e "${RED}端口 $local_port 已被使用${NC}"
        sleep 2
        return
    fi

    # 添加到原始配置
    echo "forward:${local_port}#${target}#${target_port}" >> "$RAW_CONF_PATH"
    
    # 添加规则名称
    if [ -n "$name" ]; then
        echo "${local_port}:${name}" >> "$REMARKS_PATH"
    fi

    # 设置永久有效期
    echo "${local_port}:永久" >> "$EXPIRES_PATH"

    # 重建配置文件
    rebuild_config
    
    # 重启服务
    systemctl restart gost
    
    echo -e "${GREEN}TCP+UDP 双协议转发已添加!${NC}"
    echo -e "${YELLOW}本地端口: ${local_port}${NC}"
    echo -e "${YELLOW}目标地址: ${target}:${target_port}${NC}"
    echo -e "${YELLOW}规则名称: ${name}${NC}"
    sleep 2
}

# 显示当前配置
show_config() {
    echo -e "${YELLOW}当前转发规则:${NC}"
    if [[ -f "$RAW_CONF_PATH" ]] && [[ -s "$RAW_CONF_PATH" ]]; then
        local id=1
        while IFS= read -r line; do
            local_port=$(echo "$line" | cut -d':' -f2 | cut -d'#' -f1)
            target=$(echo "$line" | cut -d'#' -f2)
            target_port=$(echo "$line" | cut -d'#' -f3)
            name=$(grep "^${local_port}:" "$REMARKS_PATH" 2>/dev/null | cut -d':' -f2- || echo "未命名")
            
            echo -e "${GREEN}$id. 端口 ${local_port} -> ${target}:${target_port} (${name})${NC}"
            ((id++))
        done < "$RAW_CONF_PATH"
    else
        echo -e "${RED}暂无转发规则${NC}"
    fi
    echo
}

# 删除转发规则（支持批量删除）
delete_rule() {
    if [ ! -f "$RAW_CONF_PATH" ] || [ ! -s "$RAW_CONF_PATH" ]; then
        echo -e "${RED}暂无转发规则${NC}"
        sleep 2
        return
    fi
    
    show_config
    echo -e "${YELLOW}请输入要删除的规则ID（多个ID用空格分隔，如：1 2 3 或 1 3）:${NC}"
    read -p "规则ID: " rule_ids
    
    if [ -z "$rule_ids" ]; then
        echo -e "${RED}未输入任何规则ID${NC}"
        sleep 2
        return
    fi

    # 将输入的ID排序并去重（从大到小排序，以便从后往前删除）
    sorted_ids=$(echo "$rule_ids" | tr ' ' '\n' | sort -nr | uniq)
    deleted_ports=""

    for rule_id in $sorted_ids; do
        if ! [[ $rule_id =~ ^[0-9]+$ ]] || [ "$rule_id" -lt 1 ]; then
            echo -e "${RED}无效的规则ID: ${rule_id}${NC}"
            continue
        fi

        local line=$(sed -n "${rule_id}p" "$RAW_CONF_PATH")
        if [ -z "$line" ]; then
            echo -e "${RED}规则ID不存在: ${rule_id}${NC}"
            continue
        fi

        local port=$(echo "$line" | cut -d':' -f2 | cut -d'#' -f1)
        
        # 删除规则
        sed -i "${rule_id}d" "$RAW_CONF_PATH"
        sed -i "/^${port}:/d" "$REMARKS_PATH" 2>/dev/null
        sed -i "/^${port}:/d" "$EXPIRES_PATH" 2>/dev/null
        sed -i "/^${port}:/d" "$TRAFFIC_PATH" 2>/dev/null
        
        deleted_ports="$deleted_ports $port"
    done

    if [ -n "$deleted_ports" ]; then
        rebuild_config
        systemctl restart gost
        echo -e "${GREEN}已删除端口:${deleted_ports}${NC}"
    else
        echo -e "${YELLOW}未删除任何规则${NC}"
    fi
    sleep 2
}

# 查看完整配置
view_full_config() {
    if [[ -f $CONFIG_FILE ]]; then
        echo -e "${YELLOW}完整配置:${NC}"
        cat $CONFIG_FILE
    else
        echo -e "${RED}配置文件不存在${NC}"
    fi
}

# 重置配置
reset_config() {
    echo -e "${YELLOW}正在重置配置...${NC}"
    create_default_config
    systemctl restart gost
    echo -e "${GREEN}配置已重置为默认状态${NC}"
}

# 显示状态
show_status() {
    systemctl status gost --no-pager -l
}

# 检查端口占用
check_port() {
    read -p "请输入要检查的端口: " port
    if ss -tuln | grep ":${port} " > /dev/null; then
        echo -e "${RED}端口 ${port} 已被占用:${NC}"
        ss -tuln | grep ":${port} "
    else
        echo -e "${GREEN}端口 ${port} 可用${NC}"
    fi
}

# 查看监听端口
show_listening_ports() {
    echo -e "${YELLOW}Gost 监听端口:${NC}"
    ss -tuln | grep gost || echo -e "${YELLOW}没有找到 Gost 监听端口${NC}"
}

# 配置管理菜单
config_menu() {
    while true; do
        echo -e "${CYAN}=== 配置管理 ===${NC}"
        echo -e "1. 添加 TCP+UDP 双协议转发"
        echo -e "2. 删除转发规则"
        echo -e "3. 查看当前配置"
        echo -e "4. 查看完整配置"
        echo -e "5. 重置所有配置"
        echo -e "6. 检查端口占用"
        echo -e "7. 查看监听端口"
        echo -e "00. 返回主菜单"
        echo -e "${CYAN}================${NC}"
        
        read -p "请选择操作 [1-7, 00]: " choice
        case $choice in
            1) add_dual_forward ;;
            2) delete_rule ;;
            3) show_config ;;
            4) view_full_config ;;
            5) reset_config ;;
            6) check_port ;;
            7) show_listening_ports ;;
            00)
                return
                ;;
            *)
                echo -e "${RED}无效选择!${NC}"
                ;;
        esac
    done
}

# 显示主菜单
show_menu() {
    clear
    show_time
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}   Gost TCP+UDP 转发脚本 v1.0.1   ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "1. 安装 Gost"
    echo -e "2. 更新 Gost"
    echo -e "3. 卸载 Gost"
    echo -e "4. 服务管理 (启动/停止/重启)"
    echo -e "5. 配置管理"
    echo -e "6. 查看状态"
    echo -e "7. 备份配置"
    echo -e "8. 导入备份"
    echo -e "9. 创建快捷方式"
    echo -e "00. 退出"
    echo -e "${BLUE}================================${NC}"
    echo -e "${YELLOW}提示: 使用命令 'g' 可快速打开此面板${NC}"
    echo
}

# 主函数
main() {
    check_root
    check_command jq

    while true; do
        show_menu
        read -p "请选择操作 [1-9, 00]: " choice
        case $choice in
            1)
                install_dependencies
                install_gost
                ;;
            2)
                update_gost
                ;;
            3)
                uninstall_gost
                ;;
            4)
                service_management
                ;;
            5)
                config_menu
                ;;
            6)
                show_status
                ;;
            7)
                backup_config
                ;;
            8)
                import_config
                ;;
            9)
                create_shortcut
                ;;
            00)
                echo -e "${GREEN}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择!${NC}"
                ;;
        esac
    done
}

# 脚本入口
if [[ $# -eq 0 ]]; then
    main
else
    case $1 in
        install)
            check_root
            install_dependencies
            install_gost
            ;;
        update)
            check_root
            update_gost
            ;;
        uninstall)
            check_root
            uninstall_gost
            ;;
        status)
            show_status
            ;;
        start)
            systemctl start gost
            ;;
        stop)
            systemctl stop gost
            ;;
        restart)
            systemctl restart gost
            ;;
        enable)
            systemctl enable gost
            ;;
        disable)
            systemctl disable gost
            ;;
        backup)
            backup_config
            ;;
        import)
            import_config
            ;;
        config)
            config_menu
            ;;
        shortcut)
            create_shortcut
            ;;
        *)
            echo "用法: $0 {install|update|uninstall|status|start|stop|restart|enable|disable|backup|import|config|shortcut}"
            exit 1
            ;;
    esac
fi
