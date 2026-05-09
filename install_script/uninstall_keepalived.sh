#!/bin/bash  
#===============================================================================  
# keepalived 卸载脚本  
#===============================================================================  
  
set -e  
  
#===============================================================================  
# 参数配置（与安装脚本保持一致）  
#===============================================================================  
#===============================================================================  
# 工具函数  
#===============================================================================  
  
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  
source "${SCRIPT_DIR}/install.conf"  

#===============================================================================  
# 步骤1: 停止并禁用 keepalived 服务  
#===============================================================================  
log_info "========== 步骤1: 停止并禁用 keepalived 服务 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "停止节点 ${NODE} keepalived"  
    ssh root@${NODE} "systemctl stop keepalived 2>/dev/null || true"  
    log_info "禁用节点 ${NODE} keepalived 开机自启"  
    ssh root@${NODE} "systemctl disable keepalived 2>/dev/null || true"  
    log_info "节点 ${NODE} keepalived 已停止并禁用"  
done  
  
#===============================================================================  
# 步骤2: 清除 VIP  
#===============================================================================  
log_info "========== 步骤2: 清除 VIP =========="  
VIP_ADDR=$(echo "${VIP}" | cut -d'/' -f1)  
for NODE in "${NODES[@]}"; do  
    if ssh root@${NODE} "ip addr show ${INTERFACE}" | grep -q "${VIP_ADDR}"; then  
        log_info "节点 ${NODE} 上检测到 VIP ${VIP}，正在删除"  
        ssh root@${NODE} "ip addr del ${VIP} dev ${INTERFACE} 2>/dev/null || true"  
        log_info "节点 ${NODE} VIP 已删除"  
    else  
        log_info "节点 ${NODE} 上未检测到 VIP，跳过"  
    fi  
done  
  
#===============================================================================  
# 步骤3: 删除 systemd 服务文件  
#===============================================================================  
log_info "========== 步骤3: 删除 systemd 服务文件 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "删除节点 ${NODE} keepalived.service"  
    ssh root@${NODE} "rm -f /usr/lib/systemd/system/keepalived.service"  
    ssh root@${NODE} "systemctl daemon-reload"  
    log_info "节点 ${NODE} systemd 服务文件已删除并重载"  
done  
  
#===============================================================================  
# 步骤4: 删除配置文件和健康检查脚本  
#===============================================================================  
log_info "========== 步骤4: 删除配置文件和健康检查脚本 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "删除节点 ${NODE} /etc/keepalived/ 目录"  
    ssh root@${NODE} "rm -rf /etc/keepalived"  
    log_info "节点 ${NODE} 配置目录已删除"  
done  
  
#===============================================================================  
# 步骤5: 删除二进制文件和安装目录  
#===============================================================================  
log_info "========== 步骤5: 删除安装文件 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "删除节点 ${NODE} keepalived 软链接"  
    ssh root@${NODE} "rm -f /usr/sbin/keepalived"  
    log_info "删除节点 ${NODE} /usr/local/keepalived/ 安装目录"  
    ssh root@${NODE} "rm -rf /usr/local/keepalived"  
    log_info "节点 ${NODE} 安装文件已删除"  
done  
  
#===============================================================================  
# 步骤6: 清理编译临时文件  
#===============================================================================  
log_info "========== 步骤6: 清理编译临时文件 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "删除节点 ${NODE} /tmp/keepalived-2.2.7 编译目录"  
    ssh root@${NODE} "rm -rf /tmp/keepalived-2.2.7 /tmp/keepalived-2.2.7.tar.gz"  
    log_info "节点 ${NODE} 编译临时文件已清理"  
done  
  
#===============================================================================  
# 步骤7: 验证卸载结果  
#===============================================================================  
log_info "========== 步骤7: 验证卸载结果 =========="  
ALL_CLEAN=true  
for NODE in "${NODES[@]}"; do  
    log_info "验证节点 ${NODE}"  
      
    # 检查服务是否还在  
    STATUS=$(ssh root@${NODE} "systemctl is-active keepalived 2>/dev/null; true")
    echo "  keepalived 服务状态: ${STATUS}"  
    if [ "${STATUS}" != "inactive" ]; then  
        log_warn "节点 ${NODE} keepalived 服务仍在运行"  
        ALL_CLEAN=false  
    fi  
      
    # 检查文件是否还存在  
    for CHECK_PATH in /usr/sbin/keepalived /usr/local/keepalived /etc/keepalived; do  
        if ssh root@${NODE} "test -e ${CHECK_PATH}"; then  
            log_warn "节点 ${NODE} ${CHECK_PATH} 仍然存在"  
            ALL_CLEAN=false  
        else  
            echo "  ${CHECK_PATH} 已清除"  
        fi  
    done  
      
    # 检查 VIP 是否还在  
    if ssh root@${NODE} "ip addr show ${INTERFACE}" | grep -q "${VIP_ADDR}"; then  
        log_warn "节点 ${NODE} VIP ${VIP_ADDR} 仍然存在"  
        ALL_CLEAN=false  
    else  
        echo "  VIP ${VIP_ADDR} 已清除"  
    fi  
done  
  
#===============================================================================  
echo ""  
if [ "${ALL_CLEAN}" = true ]; then  
    log_info "============================================="  
    log_info "  keepalived 卸载完成，所有文件已清理"  
    log_info "============================================="  
else  
    log_warn "============================================="  
    log_warn "  keepalived 卸载完成，但部分残留需手动处理"  
    log_warn "============================================="  
fi