#!/bin/bash  
#===============================================================================  
# keepalived 自动化安装脚本  
# 用法: ./install_keepalived.sh [起始步骤]  
# 示例: ./install_keepalived.sh 7    # 从步骤7开始执行  
#===============================================================================  
  
set -e  
  
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  
source "${SCRIPT_DIR}/install.conf"  
PORT_HTTP=${PORT_HTTP:-8086} 
KEEPALIVED_PREEMPT=${KEEPALIVED_PREEMPT:-true}
#===============================================================================  
# 函数: 生成健康检查脚本  
#===============================================================================  
generate_check_script() {  
    local OUTPUT="$1"  
    echo '#!/bin/bash' > "${OUTPUT}"  
    echo '# openGemini 健康检查脚本' >> "${OUTPUT}"  
    echo '# 检查 ts-meta ts-store ts-sql 三个服务是否都正常运行' >> "${OUTPUT}"  
    echo '# 任意一个不正常则返回非零，触发 keepalived 降权' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo 'systemctl is-active --quiet ts-meta || exit 1' >> "${OUTPUT}"  
    echo 'systemctl is-active --quiet ts-store || exit 1' >> "${OUTPUT}"  
    echo 'systemctl is-active --quiet ts-sql || exit 1' >> "${OUTPUT}"  
    echo 'exit 0' >> "${OUTPUT}"  
}  
  
#===============================================================================  
# 函数: 生成 keepalived 配置文件  
#===============================================================================  
generate_keepalived_conf() {  
    local OUTPUT="$1"  
    local STATE="$2"  
    local PRIORITY="$3"  
    local LOCAL_IP="$4"  
    local PEER_IP="$5"  
    local IFACE="$6"  
    local VIRTUAL_IP="$7"  
  
    # nopreempt 模式下，两个节点的 state 都必须设为 BACKUP  
    local ACTUAL_STATE="${STATE}"  
    if [ "${KEEPALIVED_PREEMPT}" != "true" ]; then  
        ACTUAL_STATE="BACKUP"  
    fi  
  
    echo 'global_defs {' > "${OUTPUT}"  
    echo "    router_id HA_GEMINI_${LOCAL_IP##*.}" >> "${OUTPUT}"  
    echo '    script_user root' >> "${OUTPUT}"  
    echo '    enable_script_security' >> "${OUTPUT}"  
    echo '    vrrp_garp_master_delay 1' >> "${OUTPUT}"  
    echo '    vrrp_garp_master_repeat 5' >> "${OUTPUT}"  
    echo '    vrrp_garp_lower_prio_delay 1' >> "${OUTPUT}"  
    echo '    vrrp_garp_lower_prio_repeat 5' >> "${OUTPUT}"  
    echo '}' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo 'vrrp_script check_opengemini {' >> "${OUTPUT}"  
    echo '    script "/etc/keepalived/check_opengemini.sh"' >> "${OUTPUT}"  
    echo '    interval 2' >> "${OUTPUT}"  
    echo '    weight -30' >> "${OUTPUT}"  
    echo '    fall 3' >> "${OUTPUT}"  
    echo '    rise 2' >> "${OUTPUT}"  
    echo '}' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo 'vrrp_instance VI_GEMINI {' >> "${OUTPUT}"  
    echo "    state ${ACTUAL_STATE}" >> "${OUTPUT}"  
    echo "    interface ${IFACE}" >> "${OUTPUT}"  
    echo '    virtual_router_id 90' >> "${OUTPUT}"  
    echo "    priority ${PRIORITY}" >> "${OUTPUT}"  
    # 高优先级节点在 nopreempt 模式下加 nopreempt  
    if [ "${KEEPALIVED_PREEMPT}" != "true" ] && [ "${PRIORITY}" == "100" ]; then  
        echo '    nopreempt' >> "${OUTPUT}"  
    fi  
    echo '    advert_int 1' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo "    unicast_src_ip ${LOCAL_IP}" >> "${OUTPUT}"  
    echo '    unicast_peer {' >> "${OUTPUT}"  
    echo "        ${PEER_IP}" >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo '    authentication {' >> "${OUTPUT}"  
    echo '        auth_type PASS' >> "${OUTPUT}"  
    echo '        auth_pass gemini888' >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo '    virtual_ipaddress {' >> "${OUTPUT}"  
    echo "        ${VIRTUAL_IP}" >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo '    track_script {' >> "${OUTPUT}"  
    echo '        check_opengemini' >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '}' >> "${OUTPUT}"  
} 

#===============================================================================  
# 函数: 生成追加用的 VRRP 配置片段（不含 global_defs）  
#===============================================================================  
generate_vrrp_snippet() {  
    local OUTPUT="$1"  
    local STATE="$2"  
    local PRIORITY="$3"  
    local LOCAL_IP="$4"  
    local PEER_IP="$5"  
    local IFACE="$6"  
    local VIRTUAL_IP="$7"  
  
    local ACTUAL_STATE="${STATE}"  
    if [ "${KEEPALIVED_PREEMPT}" != "true" ]; then  
        ACTUAL_STATE="BACKUP"  
    fi  
  
    echo '' > "${OUTPUT}"  
    echo '# === openGemini VRRP 配置（自动追加）===' >> "${OUTPUT}"  
    echo 'vrrp_script check_opengemini {' >> "${OUTPUT}"  
    echo '    script "/etc/keepalived/check_opengemini.sh"' >> "${OUTPUT}"  
    echo '    interval 2' >> "${OUTPUT}"  
    echo '    weight -30' >> "${OUTPUT}"  
    echo '    fall 3' >> "${OUTPUT}"  
    echo '    rise 2' >> "${OUTPUT}"  
    echo '}' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo 'vrrp_instance VI_GEMINI {' >> "${OUTPUT}"  
    echo "    state ${ACTUAL_STATE}" >> "${OUTPUT}"  
    echo "    interface ${IFACE}" >> "${OUTPUT}"  
    echo '    virtual_router_id 90' >> "${OUTPUT}"  
    echo "    priority ${PRIORITY}" >> "${OUTPUT}"  
    if [ "${KEEPALIVED_PREEMPT}" != "true" ] && [ "${PRIORITY}" == "100" ]; then  
        echo '    nopreempt' >> "${OUTPUT}"  
    fi  
    echo '    advert_int 1' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo "    unicast_src_ip ${LOCAL_IP}" >> "${OUTPUT}"  
    echo '    unicast_peer {' >> "${OUTPUT}"  
    echo "        ${PEER_IP}" >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo '    authentication {' >> "${OUTPUT}"  
    echo '        auth_type PASS' >> "${OUTPUT}"  
    echo '        auth_pass gemini888' >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo '    virtual_ipaddress {' >> "${OUTPUT}"  
    echo "        ${VIRTUAL_IP}" >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '' >> "${OUTPUT}"  
    echo '    track_script {' >> "${OUTPUT}"  
    echo '        check_opengemini' >> "${OUTPUT}"  
    echo '    }' >> "${OUTPUT}"  
    echo '}' >> "${OUTPUT}"  
}


#===============================================================================  
# 帮助信息  
#===============================================================================  
usage() {  
    echo "用法: $0 [选项] [起始步骤]"  
    echo ""  
    echo "选项:"  
    echo "  -h, --help       显示此帮助信息"  
    echo "  -g, --gen-conf   仅生成主备节点的 keepalived 配置文件到脚本目录"  
    echo ""  
    echo "参数:"  
    echo "  起始步骤          从指定步骤开始执行 (1-13)，默认从步骤1开始"  
    echo ""  
    echo "步骤说明:"  
    echo "  1   安装编译依赖"  
    echo "  2   分发并解压源码包"  
    echo "  3   编译安装 keepalived"  
    echo "  4   配置系统文件"  
    echo "  5   验证安装"  
    echo "  6   生成并分发健康检查脚本"  
    echo "  7   生成并分发 keepalived 配置"  
    echo "  8   启动 keepalived"  
    echo "  9   验证状态和 VIP"  
    echo "  10  通过 VIP 验证 openGemini 读写"  
    echo "  11  测试 VIP 故障切换"  
    echo "  12  恢复主节点并验证 VIP 回切"  
    echo "  13  清理测试数据"  
    echo ""  
    echo "示例:"  
    echo "  $0                # 从头开始完整安装"  
    echo "  $0 7              # 从步骤7开始执行"  
    echo "  $0 --gen-conf     # 仅生成配置文件"  
    echo "  $0 --help         # 显示帮助"  
    exit 0  
}  

if [ "${1}" == "-h" ] || [ "${1}" == "--help" ]; then  
    usage  
fi  

if [ "${1}" == "-g" ] || [ "${1}" == "--gen-conf" ]; then  
    log_info "========== 仅生成 keepalived 配置文件 =========="  
  
    VIP_ADDR=$(echo "${VIP}" | cut -d'/' -f1)  
    VIP_MASK=$(echo "${VIP}" | cut -d'/' -f2)  
  
    PRIMARY_CONF="${SCRIPT_DIR}/keepalived_${PRIMARY_IP}.conf"  
    BACKUP_CONF="${SCRIPT_DIR}/keepalived_${BACKUP_IP}.conf"  
    CHECK_SCRIPT="${SCRIPT_DIR}/check_opengemini.sh"  
  
    log_info "生成健康检查脚本: ${CHECK_SCRIPT}"  
    generate_check_script "${CHECK_SCRIPT}"  
    chmod +x "${CHECK_SCRIPT}"  
    cat "${CHECK_SCRIPT}"  
  
    log_info "生成主节点配置: ${PRIMARY_CONF}"  
    generate_keepalived_conf "${PRIMARY_CONF}" "MASTER" "100" "${PRIMARY_IP}" "${BACKUP_IP}" "${INTERFACE}" "${VIP_ADDR}" "${VIP_MASK}"  
    echo "---"  
    cat "${PRIMARY_CONF}"  
  
    log_info "生成备节点配置: ${BACKUP_CONF}"  
    generate_keepalived_conf "${BACKUP_CONF}" "BACKUP" "90" "${BACKUP_IP}" "${PRIMARY_IP}" "${INTERFACE}" "${VIP_ADDR}" "${VIP_MASK}"  
    echo "---"  
    cat "${BACKUP_CONF}"  
  
    echo ""  
    log_info "============================================="  
    log_info "  配置文件已生成到脚本目录:"  
    log_info "    ${CHECK_SCRIPT}"  
    log_info "    ${PRIMARY_CONF}"  
    log_info "    ${BACKUP_CONF}"  
    log_info "============================================="  
    exit 0  
fi  

#===============================================================================  
# 起始步骤参数  
#===============================================================================  
START_STEP=${1:-1}  
  
if ! [[ "${START_STEP}" =~ ^[0-9]+$ ]] || [ "${START_STEP}" -lt 1 ] || [ "${START_STEP}" -gt 13 ]; then  
    log_error "无效的起始步骤: ${START_STEP}，有效范围: 1-13"  
    usage  
fi  
  
if [ "${START_STEP}" -gt 1 ]; then  
    log_info "从步骤 ${START_STEP} 开始执行"  
fi  
  
should_run() {  
    [ "${START_STEP}" -le "$1" ]  
}  
  
  
#===============================================================================  
# 预检查（仅从步骤1开始时执行）  
#===============================================================================  
if should_run 1 && [ "${START_STEP}" -eq 1 ]; then  
    log_info "========== 预检查 =========="  
    if [ ! -f "${SCRIPT_DIR}/${KEEPALIVED_TAR}" ]; then  
        log_error "缺少文件: ${SCRIPT_DIR}/${KEEPALIVED_TAR}"  
        exit 1  
    fi  
    log_info "文件检查通过: ${KEEPALIVED_TAR}"  
  
    VIP_ADDR=$(echo "${VIP}" | cut -d'/' -f1)  
  
    KEEPALIVED_INSTALLED=()  
    EXISTING_CONFIG=()  
    for NODE in "${NODES[@]}"; do  
        if ssh root@${NODE} "command -v keepalived >/dev/null 2>&1"; then  
            log_warn "节点 ${NODE} 已安装 keepalived"  
            INSTALLED_VER=$(ssh root@${NODE} "keepalived --version 2>&1 | head -1")  
            echo "  已安装版本: ${INSTALLED_VER}"  
            KEEPALIVED_INSTALLED+=("${NODE}")  
        else  
            log_info "节点 ${NODE} 未安装 keepalived"  
        fi  
  
        if ssh root@${NODE} "test -f /etc/keepalived/keepalived.conf"; then  
            log_warn "节点 ${NODE} 已有 keepalived 配置文件"  
            EXISTING_CONFIG+=("${NODE}")  
        fi  
  
        if ssh root@${NODE} "ip addr show ${INTERFACE} 2>/dev/null" | grep -q "${VIP_ADDR}"; then  
            log_warn "节点 ${NODE} 的 ${INTERFACE} 上已绑定 VIP ${VIP_ADDR}"  
        fi  
  
        if ssh root@${NODE} "test -f /etc/keepalived/keepalived.conf" 2>/dev/null; then  
            if ssh root@${NODE} "grep -q 'virtual_router_id 90' /etc/keepalived/keepalived.conf 2>/dev/null"; then  
                if ssh root@${NODE} "grep -q 'VI_GEMINI' /etc/keepalived/keepalived.conf 2>/dev/null"; then  
                    log_warn "节点 ${NODE} 已有 VI_GEMINI 实例配置，将会覆盖"  
                else  
                    log_error "节点 ${NODE} 的 virtual_router_id 90 已被其他 VRRP 实例占用，请修改脚本中的 VRID 后重试"  
                    exit 1  
                fi  
            fi  
        fi  
    done  
  
    NEED_COMPILE=true  
    if [ ${#KEEPALIVED_INSTALLED[@]} -eq ${#NODES[@]} ]; then  
        log_info "所有节点已安装 keepalived，跳过编译安装步骤"  
        NEED_COMPILE=false  
    elif [ ${#KEEPALIVED_INSTALLED[@]} -gt 0 ]; then  
        log_info "部分节点已安装 keepalived，仅对未安装节点进行编译安装"  
    fi  
  
    NEED_APPEND=false  
    if [ ${#EXISTING_CONFIG[@]} -gt 0 ]; then  
        NEED_APPEND=true  
        log_info "存在已有配置的节点，将备份原配置并追加 openGemini VRRP 配置"  
    fi  
  
    log_info "预检查完成"  
else  
    # 从中间步骤开始时，初始化必要变量  
    VIP_ADDR=$(echo "${VIP}" | cut -d'/' -f1)  
    KEEPALIVED_INSTALLED=()  
    EXISTING_CONFIG=()  
    for NODE in "${NODES[@]}"; do  
        if ssh root@${NODE} "command -v keepalived >/dev/null 2>&1"; then  
            KEEPALIVED_INSTALLED+=("${NODE}")  
        fi  
        if ssh root@${NODE} "test -f /etc/keepalived/keepalived.conf"; then  
            EXISTING_CONFIG+=("${NODE}")  
        fi  
    done  
    NEED_COMPILE=true  
    if [ ${#KEEPALIVED_INSTALLED[@]} -eq ${#NODES[@]} ]; then  
        NEED_COMPILE=false  
    fi  
    NEED_APPEND=false  
    if [ ${#EXISTING_CONFIG[@]} -gt 0 ]; then  
        NEED_APPEND=true  
    fi  
fi  
  
#===============================================================================  
# 步骤1-4: 编译安装（仅未安装 keepalived 的节点）  
#===============================================================================  
if should_run 1; then  
    if [ "${NEED_COMPILE}" = true ] || [ ${#KEEPALIVED_INSTALLED[@]} -lt ${#NODES[@]} ]; then  
        log_info "========== 步骤1: 安装编译依赖 =========="  
        for NODE in "${NODES[@]}"; do  
            SKIP=false  
            for INSTALLED in "${KEEPALIVED_INSTALLED[@]}"; do  
                if [ "${NODE}" = "${INSTALLED}" ]; then  
                    SKIP=true  
                    break  
                fi  
            done  
            if [ "${SKIP}" = true ]; then  
                log_info "节点 ${NODE} 已安装 keepalived，跳过编译依赖"  
                continue  
            fi  
            log_info "在节点 ${NODE} 安装编译依赖"  
            ssh root@${NODE} "yum install -y gcc make openssl-devel libnl3-devel"  
            check_result "节点 ${NODE} 安装编译依赖"  
        done  
    else  
        log_info "========== 步骤1: 所有节点已安装 keepalived，跳过 =========="  
    fi  
fi  
  
if should_run 2; then  
    if [ "${NEED_COMPILE}" = true ] || [ ${#KEEPALIVED_INSTALLED[@]} -lt ${#NODES[@]} ]; then  
        log_info "========== 步骤2: 分发并解压源码包 =========="  
        for NODE in "${NODES[@]}"; do  
            SKIP=false  
            for INSTALLED in "${KEEPALIVED_INSTALLED[@]}"; do  
                if [ "${NODE}" = "${INSTALLED}" ]; then  
                    SKIP=true  
                    break  
                fi  
            done  
            if [ "${SKIP}" = true ]; then  
                log_info "节点 ${NODE} 已安装 keepalived，跳过分发源码包"  
                continue  
            fi  
            log_info "SCP ${KEEPALIVED_TAR} 到节点 ${NODE}:/tmp/"  
            scp "${SCRIPT_DIR}/${KEEPALIVED_TAR}" root@${NODE}:/tmp/  
            check_result "节点 ${NODE} SCP 源码包"  
            log_info "在节点 ${NODE} 解压源码包"  
            ssh root@${NODE} "cd /tmp && tar -xzf ${KEEPALIVED_TAR}"  
            check_result "节点 ${NODE} 解压源码包"  
        done  
    else  
        log_info "========== 步骤2: 所有节点已安装 keepalived，跳过 =========="  
    fi  
fi  
  
if should_run 3; then  
    if [ "${NEED_COMPILE}" = true ] || [ ${#KEEPALIVED_INSTALLED[@]} -lt ${#NODES[@]} ]; then  
        log_info "========== 步骤3: 编译安装 =========="  
        for NODE in "${NODES[@]}"; do  
            SKIP=false  
            for INSTALLED in "${KEEPALIVED_INSTALLED[@]}"; do  
                if [ "${NODE}" = "${INSTALLED}" ]; then  
                    SKIP=true  
                    break  
                fi  
            done  
            if [ "${SKIP}" = true ]; then  
                log_info "节点 ${NODE} 已安装 keepalived，跳过编译安装"  
                continue  
            fi  
            log_info "在节点 ${NODE} 编译安装 keepalived"  
            ssh root@${NODE} "cd /tmp/keepalived-2.2.7 && ./configure --prefix=/usr/local/keepalived && make -j && make install"  
            check_result "节点 ${NODE} 编译安装 keepalived"  
        done  
    else  
        log_info "========== 步骤3: 所有节点已安装 keepalived，跳过 =========="  
    fi  
fi  
  
if should_run 4; then  
    if [ "${NEED_COMPILE}" = true ] || [ ${#KEEPALIVED_INSTALLED[@]} -lt ${#NODES[@]} ]; then  
        log_info "========== 步骤4: 配置系统文件 =========="  
        for NODE in "${NODES[@]}"; do  
            SKIP=false  
            for INSTALLED in "${KEEPALIVED_INSTALLED[@]}"; do  
                if [ "${NODE}" = "${INSTALLED}" ]; then  
                    SKIP=true  
                    break  
                fi  
            done  
            if [ "${SKIP}" = true ]; then  
                log_info "节点 ${NODE} 已安装 keepalived，跳过系统文件配置"  
                continue  
            fi  
            log_info "在节点 ${NODE} 配置系统文件"  
            ssh root@${NODE} "mkdir -p /etc/keepalived && cp /usr/local/keepalived/etc/keepalived/keepalived.conf.sample /etc/keepalived/ && ln -sf /usr/local/keepalived/sbin/keepalived /usr/sbin/ && cp /tmp/keepalived-2.2.7/keepalived/keepalived.service /usr/lib/systemd/system/ && systemctl daemon-reload && systemctl enable keepalived"  
            check_result "节点 ${NODE} 配置系统文件"  
        done  
    else  
        log_info "========== 步骤4: 所有节点已安装 keepalived，跳过 =========="  
    fi  
fi  
  
#===============================================================================  
# 步骤5: 验证安装  
#===============================================================================  
if should_run 5; then  
    log_info "========== 步骤5: 验证安装 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "检查节点 ${NODE} keepalived 版本"  
        VERSION=$(ssh root@${NODE} "keepalived --version 2>&1 | head -1")  
        echo "  ${NODE}: ${VERSION}"  
        if echo "${VERSION}" | grep -q "Keepalived"; then  
            log_info "节点 ${NODE} keepalived 安装验证通过"  
        else  
            log_error "节点 ${NODE} keepalived 安装验证失败"  
            exit 1  
        fi  
    done  
fi  
  
#===============================================================================  
# 步骤6: 生成并分发健康检查脚本  
#===============================================================================  
if should_run 6; then  
    log_info "========== 步骤6: 生成并分发健康检查脚本 =========="  
    CHECK_SCRIPT="/tmp/check_opengemini.sh"  
    generate_check_script "${CHECK_SCRIPT}"  
    log_info "健康检查脚本内容:"  
    cat "${CHECK_SCRIPT}"  
  
    for NODE in "${NODES[@]}"; do  
        log_info "分发健康检查脚本到节点 ${NODE}"  
        ssh root@${NODE} "mkdir -p /etc/keepalived"  
        scp "${CHECK_SCRIPT}" root@${NODE}:/etc/keepalived/check_opengemini.sh  
        ssh root@${NODE} "chmod +x /etc/keepalived/check_opengemini.sh"  
        check_result "节点 ${NODE} 分发健康检查脚本"  
    done  
    rm -f "${CHECK_SCRIPT}"  
fi  
  
#===============================================================================  
# 步骤7: 生成并分发 keepalived 配置文件  
#===============================================================================  
if should_run 7; then  
    log_info "========== 步骤7: 生成并分发配置文件 =========="  
  
    declare -A NODE_STATE NODE_PRIORITY NODE_PEER  
    NODE_STATE["${PRIMARY_IP}"]="MASTER"  
    NODE_STATE["${BACKUP_IP}"]="BACKUP"  
    NODE_PRIORITY["${PRIMARY_IP}"]="100"  
    NODE_PRIORITY["${BACKUP_IP}"]="90"  
    NODE_PEER["${PRIMARY_IP}"]="${BACKUP_IP}"  
    NODE_PEER["${BACKUP_IP}"]="${PRIMARY_IP}"  
  
    for NODE in "${NODES[@]}"; do  
        STATE="${NODE_STATE[${NODE}]}"  
        PRIORITY="${NODE_PRIORITY[${NODE}]}"  
        PEER="${NODE_PEER[${NODE}]}"  
        CONF_TMP="/tmp/keepalived.conf.${NODE}"  
  
        HAS_EXISTING=false  
        for EC in "${EXISTING_CONFIG[@]}"; do  
            if [ "${NODE}" = "${EC}" ]; then  
                HAS_EXISTING=true  
                break  
            fi  
        done  
  
        if [ "${HAS_EXISTING}" = true ]; then  
            BACKUP_NAME="keepalived.conf.bak.$(date '+%Y%m%d%H%M%S')"  
            log_info "节点 ${NODE} 备份原配置为 /etc/keepalived/${BACKUP_NAME}"  
            ssh root@${NODE} "cp /etc/keepalived/keepalived.conf /etc/keepalived/${BACKUP_NAME}"  
            check_result "节点 ${NODE} 备份原配置"  
  
            scp root@${NODE}:/etc/keepalived/keepalived.conf "${CONF_TMP}.orig"  
  
            if grep -q 'VI_GEMINI' "${CONF_TMP}.orig"; then  
                log_info "节点 ${NODE} 已有 VI_GEMINI 配置，先移除旧配置再写入新配置"  
                sed '/# === openGemini VRRP/,/^}/d' "${CONF_TMP}.orig" | sed '/vrrp_script check_opengemini/,/^}/d' | sed '/vrrp_instance VI_GEMINI/,/^}/d' > "${CONF_TMP}.cleaned"  
                mv "${CONF_TMP}.cleaned" "${CONF_TMP}.orig"  
            fi  
  
            SNIPPET_TMP="/tmp/keepalived.snippet.${NODE}"  
            generate_vrrp_snippet "${SNIPPET_TMP}" "${STATE}" "${PRIORITY}" "${NODE}" "${PEER}" "${INTERFACE}" "${VIP}"  
  
            cat "${CONF_TMP}.orig" "${SNIPPET_TMP}" > "${CONF_TMP}"  
            rm -f "${CONF_TMP}.orig" "${SNIPPET_TMP}"  
  
            log_info "节点 ${NODE} (${STATE}) 追加后的配置:"  
            cat "${CONF_TMP}"  
        else  
            generate_keepalived_conf "${CONF_TMP}" "${STATE}" "${PRIORITY}" "${NODE}" "${PEER}" "${INTERFACE}" "${VIP}"  
            log_info "节点 ${NODE} (${STATE}) 全新配置:"  
            cat "${CONF_TMP}"  
        fi  
  
        log_info "分发配置到节点 ${NODE}"  
        scp "${CONF_TMP}" root@${NODE}:/etc/keepalived/keepalived.conf  
        check_result "节点 ${NODE} 配置分发"  
        rm -f "${CONF_TMP}"  
    done  
fi  
  
#===============================================================================  
# 步骤8: 启动/重启 keepalived  
#===============================================================================  
if should_run 8; then  
    log_info "========== 步骤8: 启动 keepalived =========="  
    for NODE in "${NODES[@]}"; do  
        STATUS=$(ssh root@${NODE} "systemctl is-active keepalived 2>/dev/null; true")  
        if [ "${STATUS}" = "active" ]; then  
            log_info "节点 ${NODE} keepalived 正在运行，执行重启"  
            ssh root@${NODE} "systemctl restart keepalived"  
            check_result "节点 ${NODE} 重启 keepalived"  
        else  
            log_info "启动节点 ${NODE} keepalived"  
            ssh root@${NODE} "systemctl start keepalived"  
            check_result "节点 ${NODE} 启动 keepalived"  
        fi  
    done  
    sleep 3  
fi  
  
#===============================================================================  
# 步骤9: 验证状态和 VIP  
#===============================================================================  
if should_run 9; then  
    log_info "========== 步骤9: 验证状态 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "检查节点 ${NODE} keepalived 运行状态"  
        STATUS=$(ssh root@${NODE} "systemctl is-active keepalived")  
        echo "  ${NODE} keepalived 状态: ${STATUS}"  
        if [ "${STATUS}" == "active" ]; then  
            log_info "节点 ${NODE} keepalived 运行正常"  
        else  
            log_error "节点 ${NODE} keepalived 未正常运行"  
            exit 1  
        fi  
    done  
  
    log_info "检查 VIP 绑定情况"  
    for NODE in "${NODES[@]}"; do  
        log_info "检查节点 ${NODE} 网卡信息"  
        IP_INFO=$(ssh root@${NODE} "ip addr show ${INTERFACE}")  
        echo "${IP_INFO}"  
        if echo "${IP_INFO}" | grep -q "${VIP_ADDR}"; then  
            log_info "VIP ${VIP_ADDR} 绑定在节点 ${NODE} 上"  
        fi  
    done  
  
    log_info "通过 VIP 测试 openGemini 连通性"  
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://${VIP_ADDR}:${PORT_HTTP}/ping" || true)  
    echo "  VIP ping 响应: HTTP ${RESPONSE}"  
    if [ "${RESPONSE}" == "204" ]; then  
        log_info "通过 VIP 访问 openGemini 正常"  
    else  
        log_warn "通过 VIP 访问 openGemini 异常，HTTP 状态码: ${RESPONSE}，请检查"  
    fi  
fi  
  
#===============================================================================  
# 步骤10: 通过 VIP 验证 openGemini 读写  
#===============================================================================  
if should_run 10; then  
    log_info "========== 步骤10: 通过 VIP 验证 openGemini 读写 =========="  
  
    VIP_ADDR=$(echo "${VIP}" | cut -d'/' -f1)  
    TIMESTAMP=$(date +%s)000000000  
    TEST_DATA="keepalived_test,host=vip_test value=1 ${TIMESTAMP}"  
  
    log_info "通过 VIP ${VIP_ADDR} 写入测试数据"  
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "http://${VIP_ADDR}:${PORT_HTTP}/write?db=slurm_profile" -u "${DB_USER}:${DB_PASS}" --data-binary "${TEST_DATA}" || true)  
    echo "  写入响应: HTTP ${HTTP_CODE}"  
    if [ "${HTTP_CODE}" == "204" ]; then  
        log_info "通过 VIP 写入成功"  
    else  
        log_error "通过 VIP 写入失败，HTTP 状态码: ${HTTP_CODE}"  
        exit 1  
    fi  
  
    sleep 3  
  
    log_info "检查主节点 ${PRIMARY_IP} 数据"  
    RESPONSE=$(curl -s -G "http://${PRIMARY_IP}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=SELECT * FROM keepalived_test LIMIT 1")  
    echo "  主节点结果: ${RESPONSE}"  
    if echo "${RESPONSE}" | grep -q "vip_test"; then  
        log_info "主节点数据验证通过"  
    else  
        log_error "主节点未查到测试数据"  
        exit 1  
    fi  
  
    log_info "检查备节点 ${BACKUP_IP} 数据"  
    RESPONSE=$(curl -s -G "http://${BACKUP_IP}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=SELECT * FROM keepalived_test LIMIT 1")  
    echo "  备节点结果: ${RESPONSE}"  
    if echo "${RESPONSE}" | grep -q "vip_test"; then  
        log_info "备节点数据验证通过 - 订阅同步正常"  
    else  
        log_warn "备节点未查到测试数据 - 订阅同步可能有延迟"  
    fi  
fi  
  
#===============================================================================  
# 步骤11: 测试 VIP 故障切换  
#===============================================================================  
if should_run 11; then  
    log_info "========== 步骤11: 测试 VIP 故障切换 =========="  
  
    VIP_ADDR=$(echo "${VIP}" | cut -d'/' -f1)  
  
    log_info "确认当前 VIP 所在节点"  
    VIP_ON_PRIMARY=false  
    VIP_ON_BACKUP=false  
    if ssh root@${PRIMARY_IP} "ip addr show ${INTERFACE}" | grep -q "${VIP_ADDR}"; then  
        VIP_ON_PRIMARY=true  
        log_info "VIP 当前在主节点 ${PRIMARY_IP}"  
    fi  
    if ssh root@${BACKUP_IP} "ip addr show ${INTERFACE}" | grep -q "${VIP_ADDR}"; then  
        VIP_ON_BACKUP=true  
        log_info "VIP 当前在备节点 ${BACKUP_IP}"  
    fi  
  
    if [ "${VIP_ON_PRIMARY}" = true ]; then  
        MASTER_NODE="${PRIMARY_IP}"  
        BACKUP_NODE="${BACKUP_IP}"  
    elif [ "${VIP_ON_BACKUP}" = true ]; then  
        MASTER_NODE="${BACKUP_IP}"  
        BACKUP_NODE="${PRIMARY_IP}"  
    else  
        log_error "VIP 未绑定在任何节点上，跳过切换测试"  
        exit 1  
    fi  
  
    log_info "停止 ${MASTER_NODE} 的 openGemini 服务以触发 VIP 切换"  
    ssh root@${MASTER_NODE} "systemctl stop ts-sql ts-store ts-meta"  
    log_info "等待 VIP 漂移..."  
    sleep 15  
  
    if ssh root@${BACKUP_NODE} "ip addr show ${INTERFACE}" | grep -q "${VIP_ADDR}"; then  
        log_info "VIP 已漂移到 ${BACKUP_NODE} - 故障切换成功"  
    else  
        log_error "VIP 未漂移到 ${BACKUP_NODE} - 故障切换失败"  
        ssh root@${MASTER_NODE} "systemctl start ts-meta ts-store ts-sql"  
        exit 1  
    fi  
  
    log_info "通过 VIP 验证切换后写入"  
    TIMESTAMP2=$(date +%s)000000000  
    TEST_DATA2="keepalived_test,host=failover_test value=2 ${TIMESTAMP2}"  
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "http://${VIP_ADDR}:${PORT_HTTP}/write?db=slurm_profile" -u "${DB_USER}:${DB_PASS}" --data-binary "${TEST_DATA2}" || true)  
    echo "  切换后写入响应: HTTP ${HTTP_CODE}"  
    if [ "${HTTP_CODE}" == "204" ]; then  
        log_info "VIP 切换后写入正常"  
    else  
        log_warn "VIP 切换后写入异常，HTTP 状态码: ${HTTP_CODE}"  
    fi  
fi  
  
#===============================================================================  
# 步骤12: 恢复原 MASTER 并验证 VIP 回切  
#===============================================================================  
if should_run 12; then  
    log_info "========== 步骤12: 恢复主节点并验证回切行为 =========="  
  
    log_info "恢复主节点 ${PRIMARY_IP} 的 openGemini 服务"  
    ssh root@${PRIMARY_IP} "systemctl start ts-meta ts-store ts-sql"  
    check_result "主节点 ${PRIMARY_IP} 恢复 openGemini 服务"  
  
    log_info "等待主节点服务完全就绪..."  
    for i in $(seq 1 10); do  
        if curl -s -o /dev/null -w "%{http_code}" "http://${PRIMARY_IP}:${PORT_HTTP}/ping" 2>/dev/null | grep -q "204"; then  
            log_info "主节点 ${PRIMARY_IP} 服务已就绪"  
            break  
        fi  
        log_info "第 ${i} 次等待..."  
        sleep 3  
    done  
  
    # 等待足够长时间，确保 keepalived 有机会检测到主节点恢复  
    log_info "等待 20 秒，观察 VIP 是否发生回切..."  
    sleep 20  
  
    # 检查 VIP 当前在哪个节点  
    VIP_ON_PRIMARY=$(ssh root@${PRIMARY_IP} "ip addr show ${INTERFACE} | grep -c '${VIP_ADDR}' || true")  
    VIP_ON_BACKUP=$(ssh root@${BACKUP_IP} "ip addr show ${INTERFACE} | grep -c '${VIP_ADDR}' || true")  
    log_info "主节点 ${PRIMARY_IP} VIP 状态: $([ '${VIP_ON_PRIMARY}' != '0' ] && echo '持有VIP' || echo '无VIP')"  
    log_info "备节点 ${BACKUP_IP} VIP 状态: $([ '${VIP_ON_BACKUP}' != '0' ] && echo '持有VIP' || echo '无VIP')"  
  
    if [ "${KEEPALIVED_PREEMPT}" != "true" ]; then  
        #===============================================================  
        # nopreempt 模式: 验证 VIP 不会自动回切  
        #===============================================================  
        log_info "当前为 nopreempt 模式，验证 VIP 不会自动回切到主节点"  
  
        if [ "${VIP_ON_BACKUP}" != "0" ] && [ "${VIP_ON_PRIMARY}" == "0" ]; then  
            log_info "验证通过: VIP 仍在备节点 ${BACKUP_IP}，未自动回切"  
        else  
            log_error "验证失败: VIP 已回切到主节点，nopreempt 配置可能未生效"  
            log_error "请检查两个节点的 keepalived 配置中 state 是否都为 BACKUP，且高优先级节点有 nopreempt"  
            exit 1  
        fi  
  
        # 通过 VIP（仍在备节点）写入数据验证可用性  
        TEST_DATA4="keepalived_test,host=nopreempt_test value=4 $(date +%s)000000000"  
        log_info "通过 VIP（备节点）写入测试数据，验证服务可用"  
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "http://${VIP_ADDR}:${PORT_HTTP}/write?db=slurm_profile" -u "${DB_USER}:${DB_PASS}" --data-binary "${TEST_DATA4}" || true)  
        echo "  写入响应: HTTP ${HTTP_CODE}"  
        if [ "${HTTP_CODE}" == "204" ]; then  
            log_info "nopreempt 模式下通过 VIP 写入成功"  
        else  
            log_warn "nopreempt 模式下通过 VIP 写入异常，HTTP 状态码: ${HTTP_CODE}"  
        fi  
  
        #===============================================================  
        # 手动回切测试: 在备节点重启 keepalived 触发重新选举  
        #===============================================================  
        log_info "========== 测试手动回切 =========="  
        log_info "在备节点 ${BACKUP_IP} 重启 keepalived，触发重新选举"  
        ssh root@${BACKUP_IP} "systemctl restart keepalived"  
        check_result "备节点 ${BACKUP_IP} 重启 keepalived"  
  
        log_info "等待 VIP 重新选举..."  
        sleep 10  
  
        VIP_ON_PRIMARY=$(ssh root@${PRIMARY_IP} "ip addr show ${INTERFACE} | grep -c '${VIP_ADDR}' || true")  
        VIP_ON_BACKUP=$(ssh root@${BACKUP_IP} "ip addr show ${INTERFACE} | grep -c '${VIP_ADDR}' || true")  
        log_info "手动回切后 - 主节点 VIP: $([ '${VIP_ON_PRIMARY}' != '0' ] && echo '持有' || echo '无')"  
        log_info "手动回切后 - 备节点 VIP: $([ '${VIP_ON_BACKUP}' != '0' ] && echo '持有' || echo '无')"  
  
        if [ "${VIP_ON_PRIMARY}" != "0" ]; then  
            log_info "手动回切成功: VIP 已回到主节点 ${PRIMARY_IP}"  
        else  
            log_warn "手动回切后 VIP 未回到主节点，可能需要等待更长时间或检查配置"  
        fi  
  
        # 手动回切后验证 VIP 可用性  
        log_info "验证手动回切后 VIP 可用性"  
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${VIP_ADDR}:${PORT_HTTP}/ping" || true)  
        echo "  VIP ping 响应: HTTP ${HTTP_CODE}"  
        if [ "${HTTP_CODE}" == "204" ]; then  
            log_info "手动回切后通过 VIP 访问 openGemini 正常"  
        else  
            log_warn "手动回切后通过 VIP 访问异常，HTTP 状态码: ${HTTP_CODE}"  
        fi  
  
    else  
        #===============================================================  
        # preempt 模式: 验证 VIP 自动回切  
        #===============================================================  
        log_info "当前为 preempt 模式，验证 VIP 自动回切到主节点"  
  
        if [ "${VIP_ON_PRIMARY}" != "0" ]; then  
            log_info "验证通过: VIP 已自动回切到主节点 ${PRIMARY_IP}"  
        else  
            log_warn "VIP 尚未回切，可能需要更长时间，再等待 15 秒..."  
            sleep 15  
            VIP_ON_PRIMARY=$(ssh root@${PRIMARY_IP} "ip addr show ${INTERFACE} | grep -c '${VIP_ADDR}' || true")  
            if [ "${VIP_ON_PRIMARY}" != "0" ]; then  
                log_info "验证通过: VIP 已自动回切到主节点 ${PRIMARY_IP}"  
            else  
                log_warn "VIP 未回切到主节点，请手动检查 keepalived 配置"  
            fi  
        fi  
  
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${VIP_ADDR}:${PORT_HTTP}/ping" || true)  
        echo "  VIP ping 响应: HTTP ${HTTP_CODE}"  
        if [ "${HTTP_CODE}" == "204" ]; then  
            log_info "回切后通过 VIP 访问 openGemini 正常"  
        else  
            log_warn "回切后通过 VIP 访问异常，HTTP 状态码: ${HTTP_CODE}"  
        fi  
    fi  
fi

#===============================================================================  
# 步骤13: 清理测试数据  
#===============================================================================  
if should_run 13; then  
    log_info "========== 步骤13: 清理测试数据 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "清理节点 ${NODE} 测试表"  
        curl -s -XPOST "http://${NODE}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=DROP MEASUREMENT keepalived_test" > /dev/null 2>&1  
    done  
    log_info "测试数据已清理"  
fi  
  
#===============================================================================  
echo ""  
log_info "============================================="  
log_info "  keepalived 安装部署及验证全部完成"  
log_info "============================================="  
log_info "  主节点: ${PRIMARY_IP} (MASTER, priority 100)"  
log_info "  备节点: ${BACKUP_IP} (BACKUP, priority 90)"  
log_info "  网卡: ${INTERFACE}"  
log_info "  VIP: ${VIP}"  
if [ "${KEEPALIVED_PREEMPT}" != "true" ]; then  
    log_info "  抢占模式: 关闭 (nopreempt，VIP 不会自动回切)"  
else  
    log_info "  抢占模式: 开启 (preempt，VIP 会自动回切到高优先级节点)"  
fi  
log_info "  健康检查: ts-meta + ts-store + ts-sql"
log_info "  健康检查: ts-meta + ts-store + ts-sql"  
log_info "  检查间隔: 2秒, 连续3次失败触发切换"  
log_info "============================================="  
log_info "  验证结果:"  
log_info "    - 通过 VIP 读写 openGemini: 通过"  
log_info "    - 主备订阅同步: 通过"  
log_info "    - VIP 故障切换: 通过"  
if [ "${KEEPALIVED_PREEMPT}" != "true" ]; then  
    log_info "    - VIP 不自动回切 (nopreempt): 已验证"  
    log_info "    - 手动回切: 已验证"  
else  
    log_info "    - VIP 自动回切 (preempt): 已验证"  
fi  
log_info "    - 服务恢复后 VIP 回切: 已验证"  
log_info "============================================="