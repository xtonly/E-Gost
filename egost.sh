#!/bin/bash

# ==================================================
# 面板信息# 
PANEL_VERSION="1.2"
UPDATE_LOG="v1.2: 优化菜单显示; 增加端口占用实时检测."
# ==================================================

CONFIG_FILE="/etc/gost/config.yaml"
SERVICE_FILE="/etc/systemd/system/gost.service"
BINARY_PATH="/usr/local/bin/gost"
CONFIG_BACKUP_DIR="/etc/gost/backups"
RAW_CONF_PATH="/etc/gost/rawconf"
REMARKS_PATH="/etc/gost/remarks.txt"
EXPIRES_PATH="/etc/gost/expires.txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[1;35m'
NC='\033[0m'

# 显示当前时间
show_time() {
    echo -e "${YELLOW}当前时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
}

# 获取Gost版本
get_gost_version() {
    if [[ -f "$BINARY_PATH" ]]; then
        $BINARY_PATH -V 2>/dev/null | head -n 1 | awk '{print $2}' || echo "未安装"
    else
        echo "未安装"
    fi
}

# 获取Gost状态
get_gost_status() {
    if systemctl is-active gost >/dev/null 2>&1; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}已停止${NC}"
    fi
}

# 获取转发规则统计
get_rules_stats() {
    local active_count=0
    local expired_count=0
    local current_time=$(date +%s)
    
    if [[ -f "$EXPIRES_PATH" ]]; then
        while IFS=: read -r port expire_date; do
            if [ "$expire_date" = "永久" ] || [ "$expire_date" -gt "$current_time" ]; then
                ((active_count++))
            else
                ((expired_count++))
            fi
        done < "$EXPIRES_PATH"
    fi
    
    echo "$active_count $expired_count"
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

    # 添加Gost监控定时任务
    add_gost_monitor_cron

    echo -e "${GREEN}Gost 安装完成!${NC}"
    echo -e "${YELLOW}请使用配置菜单设置转发规则${NC}"
}

# 添Gost监控定时任务
add_gost_monitor_cron() {
    cat > /usr/local/bin/gost-monitor.sh << 'EOF'
#!/bin/bash

# Gost 服务监控脚本
# 每小时检查一次Gost是否运行，如果没有运行则重启

if ! systemctl is-active gost >/dev/null 2>&1; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Gost 服务未运行，正在重启..." >> /var/log/gost-monitor.log
    systemctl restart gost
    if systemctl is-active gost >/dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Gost 服务重启成功" >> /var/log/gost-monitor.log
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Gost 服务重启失败" >> /var/log/gost-monitor.log
    fi
fi
EOF

    chmod +x /usr/local/bin/gost-monitor.sh
    echo "0 * * * * root /usr/local/bin/gost-monitor.sh >/dev/null 2>&1" > /etc/cron.d/gost-monitor
}

# 创建快捷方式
create_shortcut() {
    echo -e "${YELLOW}创建快捷命令...${NC}"
    
    # 获取当前脚本的绝对路径
    local script_path=$(readlink -f "$0")
    local script_name=$(basename "$script_path")
    
    # 复制脚本到系统路径
    cp "$script_path" /usr/local/bin/gost-manager.sh
    chmod +x /usr/local/bin/gost-manager.sh
    
    # 创建软链接
    ln -sf /usr/local/bin/gost-manager.sh /usr/bin/zf
    
    echo -e "${GREEN}快捷命令 'zf' 创建成功!${NC}"
    echo -e "${YELLOW}现在可以使用 'zf' 命令快速打开管理面板${NC}"
}

# 删除快捷方式
delete_shortcut() {
    echo -e "${YELLOW}当前已存在的快捷方式:${NC}"
    
    local shortcuts=()
    local shortcut_paths=()
    
    # 查找所有快捷方式
    if [[ -L "/usr/bin/zf" ]]; then
        shortcuts+=("zf")
        shortcut_paths+=("/usr/bin/zf")
    fi
    
    if [[ -L "/usr/bin/g" ]]; then
        shortcuts+=("g")
        shortcut_paths+=("/usr/bin/g")
    fi
    
    if [[ ${#shortcuts[@]} -eq 0 ]]; then
        echo -e "${RED}没有找到任何快捷方式${NC}"
        sleep 2
        return
    fi
    
    # 显示快捷方式列表
    for i in "${!shortcuts[@]}"; do
        echo "$((i+1)). ${shortcuts[$i]} -> $(readlink -f ${shortcut_paths[$i]})"
    done
    echo "99. 删除所有快捷方式"
    echo "00. 返回"
    
    read -p "请选择要删除的快捷方式编号 (多个用空格分隔): " choices
    
    if [[ "$choices" == "00" ]]; then
        return
    fi
    
    if [[ "$choices" == "99" ]]; then
        for path in "${shortcut_paths[@]}"; do
            rm -f "$path"
            echo -e "${YELLOW}已删除快捷方式: $(basename $path)${NC}"
        done
        echo -e "${GREEN}所有快捷方式已删除${NC}"
        sleep 2
        return
    fi
    
    # 处理多个选择
    local deleted=0
    for choice in $choices; do
        if [[ $choice -ge 1 && $choice -le ${#shortcuts[@]} ]]; then
            local index=$((choice-1))
            rm -f "${shortcut_paths[$index]}"
            echo -e "${YELLOW}已删除快捷方式: ${shortcuts[$index]}${NC}"
            ((deleted++))
        else
            echo -e "${RED}无效的选择: $choice${NC}"
        fi
    done
    
    if [[ $deleted -gt 0 ]]; then
        echo -e "${GREEN}已删除 $deleted 个快捷方式${NC}"
    else
        echo -e "${YELLOW}未删除任何快捷方式${NC}"
    fi
    sleep 2
}

# 快捷方式管理菜单
shortcut_menu() {
    while true; do
        echo -e "${CYAN}=== 快捷方式管理 ===${NC}"
        echo -e "1. 创建快捷方式 (zf)"
        echo -e "2. 删除快捷方式"
        echo -e "00. 返回主菜单"
        echo -e "${CYAN}===================${NC}"
        
        read -p "请选择操作 [1-2, 00]: " choice
        case $choice in
            1)
                create_shortcut
                ;;
            2)
                delete_shortcut
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

# 创建默认配置 (使用 YAML 格式)
create_default_config() {
    cat > $CONFIG_FILE << 'EOF'
# Gost 端口转发配置
# 用于转发 Reality 和 Shadowsocks 流量

services: []
EOF
    
    # 初始化其他配置文件
    touch $RAW_CONF_PATH $REMARKS_PATH $EXPIRES_PATH
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

# 备份配置
backup_config() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local hostname=$(hostname)
    local backup_name="${hostname}_backup_${timestamp}"
    
    cp $CONFIG_FILE "$CONFIG_BACKUP_DIR/${backup_name}.yaml"
    cp $RAW_CONF_PATH "$CONFIG_BACKUP_DIR/${backup_name}_rawconf"
    cp $REMARKS_PATH "$CONFIG_BACKUP_DIR/${backup_name}_remarks.txt"
    cp $EXPIRES_PATH "$CONFIG_BACKUP_DIR/${backup_name}_expires.txt"
    echo -e "${GREEN}配置已备份到: $CONFIG_BACKUP_DIR/${backup_name}.yaml${NC}"
}

# 导入备份配置
import_config() {
    echo -e "${YELLOW}可用备份文件:${NC}"
    local backups=($(ls -1 $CONFIG_BACKUP_DIR/*.yaml 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${RED}没有找到备份文件，请先备份！${NC}"
        sleep 2
        return 1
    fi

    for i in "${!backups[@]}"; do
        echo "$((i+1)). ${backups[$i]}"
    done

    read -p "请选择要恢复的备份文件编号: " choice
    if [[ $choice -ge 1 && $choice -le ${#backups[@]} ]]; then
        local selected_file="${backups[$((choice-1))]}"
        local base_name=$(basename "$selected_file" .yaml)
        
        cp "$selected_file" $CONFIG_FILE
        cp "$CONFIG_BACKUP_DIR/${base_name}_rawconf" $RAW_CONF_PATH 2>/dev/null
        cp "$CONFIG_BACKUP_DIR/${base_name}_remarks.txt" $REMARKS_PATH 2>/dev/null
        cp "$CONFIG_BACKUP_DIR/${base_name}_expires.txt" $EXPIRES_PATH 2>/dev/null
        
        systemctl restart gost
        echo -e "${GREEN}配置已从备份恢复${NC}"
    else
        echo -e "${RED}无效的选择${NC}"
    fi
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
    rm -f /usr/local/bin/gost-monitor.sh
    rm -f /etc/cron.d/gost-monitor
    rm -f /usr/local/bin/gost-manager.sh
    rm -f /usr/bin/zf
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
        echo -e "5. 启用开机自启"
        echo -e "6. 禁用开机自启"
        echo -e "00. 返回主菜单"
        echo -e "${CYAN}================${NC}"
        
        read -p "请选择操作 [1-6, 00]: " choice
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
                systemctl enable gost
                echo -e "${GREEN}已启用开机自启${NC}"
                ;;
            6)
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
    echo -e "${YELLOW}添加 TCP+UDP 双协议转发规则...${NC}"
    
    while true; do
        read -p "请输入本地监听端口 (输入 0 返回): " local_port

        if [[ "$local_port" == "0" ]]; then
            echo -e "${YELLOW}已取消操作。${NC}"
            return
        fi

        if [[ ! $local_port =~ ^[0-9]+$ ]] || [[ "$local_port" -lt 1 ]] || [[ "$local_port" -gt 65535 ]]; then
            echo -e "${RED}错误: 端口无效! 必须是1-65535之间的数字，请重新输入。${NC}"
            continue
        fi

        # 检查系统级端口占用
        if ss -tuln | grep -q ":${local_port} "; then
            echo -e "${RED}错误: 端口 ${local_port} 正在被其他程序占用，请重新输入!${NC}"
            continue
        fi
        
        # 检查是否已被Gost规则使用
        if grep -q ":${local_port}#" "$RAW_CONF_PATH" 2>/dev/null; then
            echo -e "${RED}错误: 端口 ${local_port} 已被其他Gost规则使用，请重新输入!${NC}"
            continue
        fi

        echo -e "${GREEN}端口 ${local_port} 可用，请继续...${NC}"
        break
    done

    read -p "请输入目标地址: " target
    read -p "请输入目标端口: " target_port
    read -p "请输入规则备注 (可选): " name

    if [[ ! $target_port =~ ^[0-9]+$ ]] || [[ "$target_port" -lt 1 ]] || [[ "$target_port" -gt 65535 ]]; then
        echo -e "${RED}添加失败: 目标端口无效! 必须是1-65535之间的数字。${NC}"
        sleep 2
        return
    fi
    
    if [[ -z "$name" ]]; then
        name="未命名规则"
    fi

    # 添加到原始配置
    echo "forward:${local_port}#${target}#${target_port}" >> "$RAW_CONF_PATH"
    
    # 添加规则备注
    echo "${local_port}:${name}" >> "$REMARKS_PATH"

    # 设置永久有效期
    echo "${local_port}:永久" >> "$EXPIRES_PATH"

    # 重建配置文件
    rebuild_config
    
    # 重启服务
    systemctl restart gost
    
    echo -e "${GREEN}添加成功! TCP+UDP 双协议转发已生效。${NC}"
    echo -e "${YELLOW}  本地端口: ${local_port}${NC}"
    echo -e "${YELLOW}  目标地址: ${target}:${target_port}${NC}"
    echo -e "${YELLOW}  规则备注: ${name}${NC}"
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

# 删除所有转发规则
delete_all_rules() {
    if [ ! -f "$RAW_CONF_PATH" ] || [ ! -s "$RAW_CONF_PATH" ]; then
        echo -e "${RED}暂无转发规则${NC}"
        sleep 2
        return
    fi
    
    read -p "确定要删除所有转发规则吗？(y/n): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${YELLOW}已取消操作${NC}"
        sleep 2
        return
    fi
    
    # 清空所有配置文件
    > "$RAW_CONF_PATH"
    > "$REMARKS_PATH"
    > "$EXPIRES_PATH"
    
    # 重建配置
    rebuild_config
    systemctl restart gost
    
    echo -e "${GREEN}已删除所有转发规则${NC}"
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

# 检查端口占用
check_port() {
    read -p "请输入要检查的端口: " port
    if ss -tuln | grep ":${port} " > /dev/null; then
        echo -e "${RED}================================${NC}"
        echo -e "${RED}〓〓〓 端口 ${port} 已被占用 〓〓〓${NC}"
        echo -e "${RED}================================${NC}"
        ss -tuln | grep ":${port} "
        echo -e "${RED}================================${NC}"
    else
        echo -e "${PURPLE}================================${NC}"
        echo -e "${PURPLE}〓〓〓 端口 ${port} 可用 〓〓〓${NC}"
        echo -e "${PURPLE}================================${NC}"
    fi
}

# 配置管理菜单
config_menu() {
    while true; do
        echo -e "${CYAN}=== 配置管理 ===${NC}"
        echo -e "1. 添加 TCP+UDP 双协议转发"
        echo -e "2. 删除转发规则"
        echo -e "3. 删除所有转发规则"
        echo -e "4. 查看当前配置"
        echo -e "5. 查看完整配置"
        echo -e "6. 检查端口占用"
        echo -e "00. 返回主菜单"
        echo -e "${CYAN}================${NC}"
        
        read -p "请选择操作 [1-6, 00]: " choice
        case $choice in
            1) add_dual_forward ;;
            2) delete_rule ;;
            3) delete_all_rules ;;
            4) show_config ;;
            5) view_full_config ;;
            6) check_port ;;
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
    
    # 获取系统信息
    local gost_version=$(get_gost_version)
    local gost_status=$(get_gost_status)
    local stats=$(get_rules_stats)
    local active_count=$(echo $stats | awk '{print $1}')
    local expired_count=$(echo $stats | awk '{print $2}')
    
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}           E-Gost 转发面板          ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "面板版本: ${GREEN}v${PANEL_VERSION}${NC}"
    echo -e "Gost 版本: ${YELLOW}${gost_version}${NC}"
    echo -e "更新日志: ${YELLOW}${UPDATE_LOG}${NC}"
    echo -e "${BLUE}--------------------------------${NC}"
    echo -e "服务状态: ${gost_status}"
    echo -e "转发规则: ${GREEN}有效 ${active_count}${NC} | ${RED}过期 ${expired_count}${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "1. 安装 Gost (v3.2.4)"
    echo -e "2. 卸载 Gost"
    echo -e "3. 服务管理 (启动/停止/重启)"
    echo -e "4. 配置管理"
    echo -e "5. 备份配置"
    echo -e "6. 导入备份"
    echo -e "7. 快捷方式管理"
    echo -e "00. 退出"
    echo -e "${BLUE}================================${NC}"
    echo -e "${YELLOW}提示: 使用命令 'zf' 可快速打开此面板${NC}"
    echo
}

# 主函数
main() {
    check_root
    check_command jq

    while true; do
        show_menu
        read -p "请选择操作 [1-7, 00]: " choice
        case $choice in
            1)
                install_dependencies
                install_gost
                ;;
            2)
                uninstall_gost
                ;;
            3)
                service_management
                ;;
            4)
                config_menu
                ;;
            5)
                backup_config
                ;;
            6)
                import_config
                ;;
            7)
                shortcut_menu
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
        uninstall)
            check_root
            uninstall_gost
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
            shortcut_menu
            ;;
        *)
            echo "用法: $0 {install|uninstall|start|stop|restart|enable|disable|backup|import|config|shortcut}"
            exit 1
            ;;
    esac
fi
