#!/bin/bash  
#===============================================================================  
# openGemini 卸载脚本  
#===============================================================================  
  
set -e  
  
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  
source "${SCRIPT_DIR}/install.conf"  
  
#===============================================================================  
# 部署模式  
#===============================================================================  
DEPLOY_MODE="${DEPLOY_MODE:-dual}"  
if [ "${DEPLOY_MODE}" == "single" ]; then  
    NODES=("${PRIMARY_IP}")  
else  
    NODES=("${PRIMARY_IP}" "${BACKUP_IP}")  
fi  
  
log_info "卸载模式: ${DEPLOY_MODE}, 目标节点: ${NODES[*]}"  
  
#===============================================================================  
# 步骤1: 停止服务  
#===============================================================================  
log_info "========== 步骤1: 停止服务 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "停止节点 ${NODE} 的 ts-sql ts-store ts-meta"  
    ssh root@${NODE} "systemctl stop ts-sql 2>/dev/null; systemctl stop ts-store 2>/dev/null; systemctl stop ts-meta 2>/dev/null; true"  
    log_info "节点 ${NODE} 服务已停止"  
done  
  
#===============================================================================  
# 步骤2: 禁用服务并移除 service 文件  
#===============================================================================  
log_info "========== 步骤2: 禁用服务并移除 service 文件 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "禁用节点 ${NODE} 开机自启"  
    ssh root@${NODE} "systemctl disable ts-meta 2>/dev/null; systemctl disable ts-store 2>/dev/null; systemctl disable ts-sql 2>/dev/null; true"  
  
    log_info "删除节点 ${NODE} service 文件"  
    ssh root@${NODE} "rm -f /usr/lib/systemd/system/ts-meta.service /usr/lib/systemd/system/ts-store.service /usr/lib/systemd/system/ts-sql.service"  
  
    log_info "节点 ${NODE} daemon-reload"  
    ssh root@${NODE} "systemctl daemon-reload"  
    log_info "节点 ${NODE} service 文件已清理"  
done  
  
#===============================================================================  
# 步骤3: 删除环境变量配置  
#===============================================================================  
log_info "========== 步骤3: 删除环境变量配置 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "删除节点 ${NODE} /etc/profile.d/opengemini.sh"  
    ssh root@${NODE} "rm -f /etc/profile.d/opengemini.sh"  
    log_info "节点 ${NODE} 环境变量已清理"  
done  
  
#===============================================================================  
# 步骤4: 删除安装目录（含数据、配置、二进制）  
#===============================================================================  
log_info "========== 步骤4: 删除安装目录 =========="  
for NODE in "${NODES[@]}"; do  
    log_info "删除节点 ${NODE} ${INSTALL_PATH}"  
    ssh root@${NODE} "rm -rf ${INSTALL_PATH}"  
    log_info "节点 ${NODE} 安装目录已删除"  
done  
  
#===============================================================================  
# 步骤5: 验证卸载结果  
#===============================================================================  
log_info "========== 步骤5: 验证卸载结果 =========="  
ALL_CLEAN=true  
for NODE in "${NODES[@]}"; do  
    log_info "验证节点 ${NODE}"  
  
    for SVC in ts-meta ts-store ts-sql; do  
        STATUS=$(ssh root@${NODE} "systemctl is-active ${SVC} 2>/dev/null; true")  
        echo "  ${SVC} 状态: ${STATUS}"  
        if [ "${STATUS}" != "inactive" ] && [ "${STATUS}" != "unknown" ]; then  
            log_warn "节点 ${NODE} ${SVC} 仍在运行"  
            ALL_CLEAN=false  
        fi  
    done  
  
    for CHECK_PATH in "${INSTALL_PATH}" /usr/lib/systemd/system/ts-meta.service /usr/lib/systemd/system/ts-store.service /usr/lib/systemd/system/ts-sql.service /etc/profile.d/opengemini.sh; do  
        if ssh root@${NODE} "test -e ${CHECK_PATH}"; then  
            log_warn "节点 ${NODE} ${CHECK_PATH} 仍然存在"  
            ALL_CLEAN=false  
        else  
            echo "  ${CHECK_PATH} 已清除"  
        fi  
    done  
done  
  
#===============================================================================  
echo ""  
if [ "${ALL_CLEAN}" = true ]; then  
    log_info "============================================="  
    log_info "  openGemini 卸载完成，所有文件已清理"  
    log_info "  部署模式: ${DEPLOY_MODE}"  
    log_info "  已卸载节点: ${NODES[*]}"  
    log_info "============================================="  
else  
    log_warn "============================================="  
    log_warn "  openGemini 卸载完成，但部分残留需手动处理"  
    log_warn "  部署模式: ${DEPLOY_MODE}"  
    log_warn "  目标节点: ${NODES[*]}"  
    log_warn "============================================="  
fi