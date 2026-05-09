#!/bin/bash  
#===============================================================================  
# openGemini 自动化安装脚本  
# 用法: ./install_opengemini.sh [选项] [起始步骤]  
# 示例: ./install_opengemini.sh 8    # 从步骤8开始执行  
#===============================================================================  
  
set -e  
  
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  
source "${SCRIPT_DIR}/install.conf"  
  
#===============================================================================  
# 部署模式（install.conf 未定义则默认 dual）  
# single: 单节点，仅部署 PRIMARY_IP，无订阅  
# dual:   主备双节点，PRIMARY_IP + BACKUP_IP，含订阅同步  
#===============================================================================  
DEPLOY_MODE=${DEPLOY_MODE:-dual}  
  
if [ "${DEPLOY_MODE}" == "single" ]; then  
    NODES=("${PRIMARY_IP}")  
    TOTAL_STEPS=10  
    log_info "部署模式: 单节点 (${PRIMARY_IP})"  
elif [ "${DEPLOY_MODE}" == "dual" ]; then  
    NODES=("${PRIMARY_IP}" "${BACKUP_IP}")  
    TOTAL_STEPS=12  
    log_info "部署模式: 主备双节点 (${PRIMARY_IP}, ${BACKUP_IP})"  
else  
    log_error "无效的 DEPLOY_MODE: ${DEPLOY_MODE}，可选值: single, dual"  
    exit 1  
fi  
  
#===============================================================================  
# 端口配置（如 install.conf 未定义则使用默认值）  
#===============================================================================  
PORT_HTTP=${PORT_HTTP:-8086}  
PORT_FLIGHT=${PORT_FLIGHT:-8087}  
PORT_META_BIND=${PORT_META_BIND:-8088}  
PORT_META_HTTP=${PORT_META_HTTP:-8091}  
PORT_META_RPC=${PORT_META_RPC:-8092}  
PORT_STORE_INGEST=${PORT_STORE_INGEST:-8400}  
PORT_STORE_SELECT=${PORT_STORE_SELECT:-8401}  
PORT_GOSSIP_META=${PORT_GOSSIP_META:-8010}  
PORT_GOSSIP_STORE=${PORT_GOSSIP_STORE:-8011}  
PORT_GOSSIP_SQL=${PORT_GOSSIP_SQL:-8012}  
  
REQUIRED_PORTS=(${PORT_HTTP} ${PORT_FLIGHT} ${PORT_META_BIND} ${PORT_META_HTTP} ${PORT_META_RPC} ${PORT_STORE_INGEST} ${PORT_STORE_SELECT} ${PORT_GOSSIP_META} ${PORT_GOSSIP_STORE} ${PORT_GOSSIP_SQL})  
  
CREATE_MEASUREMENTS_PRIMARY=${CREATE_MEASUREMENTS_PRIMARY:-true}  
CREATE_MEASUREMENTS_BACKUP=${CREATE_MEASUREMENTS_BACKUP:-true}

usage() {  
    echo "用法: $0 [选项] [起始步骤]"  
    echo ""  
    echo "选项:"  
    echo "  -h, --help    显示此帮助信息"  
    echo ""  
    echo "部署模式 (在 install.conf 中设置 DEPLOY_MODE):"  
    echo "  single  单节点部署，仅部署主节点，无订阅同步 (步骤1-10)"  
    echo "  dual    主备双节点部署，含订阅同步 (步骤1-12，默认)"  
    echo "  主节点建表:     ${CREATE_MEASUREMENTS_PRIMARY}"  
    echo "  备节点建表:     ${CREATE_MEASUREMENTS_BACKUP}"
    echo ""  
    echo "参数:"  
    echo "  起始步骤       从指定步骤开始执行 (1-${TOTAL_STEPS})，默认从步骤1开始"  
    echo ""  
    echo "步骤说明:"  
    echo "  1   创建安装路径"  
    echo "  2   拷贝压缩包并解压"  
    echo "  3   修改配置文件并分发"  
    echo "  4   配置 systemd 服务"  
    echo "  5   配置环境变量"  
    echo "  6   启动服务"  
    echo "  7   创建管理员用户"  
    echo "  8   开启鉴权并重启服务"  
    echo "  9   创建数据库 slurm_profile"  
    echo "  10  创建 measurements"  
    if [ "${DEPLOY_MODE}" == "dual" ]; then  
        echo "  11  创建订阅 (主 -> 备)"  
        echo "  12  安装验证 (写入测试数据、检查订阅同步)"  
    fi  
    echo ""  
    echo "当前配置:"  
    echo "  部署模式:       ${DEPLOY_MODE}"  
    echo "  节点列表:       ${NODES[*]}"  
    echo "  HTTP API:       ${PORT_HTTP}"  
    echo "  Flight:         ${PORT_FLIGHT}"  
    echo "  Meta Bind:      ${PORT_META_BIND}"  
    echo "  Meta HTTP:      ${PORT_META_HTTP}"  
    echo "  Meta RPC:       ${PORT_META_RPC}"  
    echo "  Store Ingest:   ${PORT_STORE_INGEST}"  
    echo "  Store Select:   ${PORT_STORE_SELECT}"  
    echo "  Gossip Meta:    ${PORT_GOSSIP_META}"  
    echo "  Gossip Store:   ${PORT_GOSSIP_STORE}"  
    echo "  Gossip SQL:     ${PORT_GOSSIP_SQL}"  
    echo ""  
    echo "示例:"  
    echo "  $0           # 从头开始完整安装"  
    echo "  $0 8         # 从步骤8开始执行"  
    echo "  $0 --help    # 显示帮助"  
    exit 0  
}  
  
#===============================================================================  
# 起始步骤参数  
#===============================================================================  
if [ "${1}" == "-h" ] || [ "${1}" == "--help" ]; then  
    usage  
fi  
  
START_STEP=${1:-1}  
  
if ! [[ "${START_STEP}" =~ ^[0-9]+$ ]] || [ "${START_STEP}" -lt 1 ] || [ "${START_STEP}" -gt "${TOTAL_STEPS}" ]; then  
    log_error "无效的起始步骤: ${START_STEP}，有效范围: 1-${TOTAL_STEPS} (当前模式: ${DEPLOY_MODE})"  
    usage  
fi  
  
log_info "从步骤 ${START_STEP} 开始执行 (共 ${TOTAL_STEPS} 步)"  
log_info "端口配置: HTTP=${PORT_HTTP} Flight=${PORT_FLIGHT} MetaBind=${PORT_META_BIND} MetaHTTP=${PORT_META_HTTP} MetaRPC=${PORT_META_RPC} StoreIngest=${PORT_STORE_INGEST} StoreSelect=${PORT_STORE_SELECT}"  
  
#===============================================================================  
# 函数: 判断当前步骤是否需要执行  
#===============================================================================  
should_run() {  
    local STEP_NUM=$1  
    [ "${STEP_NUM}" -ge "${START_STEP}" ]  
}  
  
#===============================================================================  
# 预检查（仅从步骤1开始时执行）  
#===============================================================================  
if should_run 1 && [ "${START_STEP}" -eq 1 ]; then  
    log_info "========== 预检查 =========="  
    for FILE in "${ZIP_FILE}" "${CONF_TEMPLATE}" ts-meta.service ts-sql.service ts-store.service; do  
        if [ ! -f "${SCRIPT_DIR}/${FILE}" ]; then  
            log_error "缺少文件: ${SCRIPT_DIR}/${FILE}"  
            exit 1  
        fi  
        log_info "文件检查通过: ${FILE}"  
    done  
  
    log_info "========== 预检查: 端口占用 =========="  
    PORT_CONFLICT=false  
    for NODE in "${NODES[@]}"; do  
        log_info "检查节点 ${NODE} 端口"  
        for PORT in "${REQUIRED_PORTS[@]}"; do  
            RESULT=$(ssh root@${NODE} "ss -tlnp | grep ':${PORT} ' || true")  
            if [ -n "${RESULT}" ]; then  
                log_error "节点 ${NODE} 端口 ${PORT} 已被占用: ${RESULT}"  
                PORT_CONFLICT=true  
            else  
                echo "  ${NODE}:${PORT} 可用"  
            fi  
        done  
    done  
  
    if [ "${PORT_CONFLICT}" = true ]; then  
        log_error "存在端口冲突，请先释放被占用的端口后再执行安装"  
        exit 1  
    fi  
    log_info "所有端口检查通过"  
fi  
  
#===============================================================================  
# 函数: 根据节点IP生成配置文件  
#===============================================================================  
generate_conf() {  
    local NODE_IP="$1"  
    local OUTPUT="$2"  
  
    cp "${SCRIPT_DIR}/${CONF_TEMPLATE}" "${OUTPUT}"  
  
    # 替换地址占位符  
    sed -i "s|{{addr}}|${NODE_IP}|g" "${OUTPUT}"  
    sed -i "s|{{meta_addr_1}}|${NODE_IP}|g" "${OUTPUT}"  
    sed -i "s|{{meta_addr_2}}|${NODE_IP}|g" "${OUTPUT}"  
    sed -i "s|{{meta_addr_3}}|${NODE_IP}|g" "${OUTPUT}"  
    sed -i "s|{{id}}|1|g" "${OUTPUT}"  
  
    # meta-join 合并为单节点（用新端口）  
    sed -i "s|meta-join = \[\"${NODE_IP}:8092\", \"${NODE_IP}:8092\", \"${NODE_IP}:8092\"\]|meta-join = [\"${NODE_IP}:${PORT_META_RPC}\"]|" "${OUTPUT}"  
  
    # 基础配置  
    sed -i 's|# ha-policy = "write-available-first"|ha-policy = "write-available-first"|' "${OUTPUT}"  
    sed -i 's|# ignore-empty-tag = false|ignore-empty-tag = true|' "${OUTPUT}"  
  
    # 路径替换  
    sed -i "s|dir = \"/tmp/openGemini/data/meta/1\"|dir = \"${INSTALL_PATH}/meta\"|" "${OUTPUT}"  
    sed -i "s|store-data-dir = \"/tmp/openGemini/data\"|store-data-dir = \"${INSTALL_PATH}/\"|" "${OUTPUT}"  
    sed -i "s|store-wal-dir = \"/tmp/openGemini/data\"|store-wal-dir = \"${INSTALL_PATH}/\"|" "${OUTPUT}"  
    sed -i "s|store-meta-dir = \"/tmp/openGemini/data/meta/1\"|store-meta-dir = \"${INSTALL_PATH}/meta\"|" "${OUTPUT}"  
    sed -i "s|path = \"/tmp/openGemini/logs/1\"|path = \"${INSTALL_PATH}/log\"|" "${OUTPUT}"  
    sed -i "s|export-dir = \"/tmp/openGemini/export\"|export-dir = \"${INSTALL_PATH}/export\"|" "${OUTPUT}"  
  
    # gossip 关闭并合并为单节点  
    sed -i '/^\[gossip\]/,/^\[/{s|enabled = true|enabled = false|}' "${OUTPUT}"  
    sed -i "s|members = \[\"${NODE_IP}:8010\", \"${NODE_IP}:8010\", \"${NODE_IP}:8010\"\]|members = [\"${NODE_IP}:${PORT_GOSSIP_META}\"]|" "${OUTPUT}"  
  
    # [http] bind-address 改为 0.0.0.0  
    sed -i '/^\[http\]/,/^\[/{s|bind-address = "'"${NODE_IP}"':8086"|bind-address = "0.0.0.0:'"${PORT_HTTP}"'"|}' "${OUTPUT}"  
  
    # subscriber: 双节点模式启用，单节点模式保持关闭  
    if [ "${DEPLOY_MODE}" == "dual" ]; then  
        sed -i '/^\[subscriber\]/,/^\[/{s|# enabled = false|enabled = true|}' "${OUTPUT}"  
    fi  
  
    # 端口替换（替换默认端口为自定义端口）  
    if [ "${PORT_FLIGHT}" != "8087" ]; then  
        sed -i "s|${NODE_IP}:8087|${NODE_IP}:${PORT_FLIGHT}|g" "${OUTPUT}"  
        sed -i "s|0.0.0.0:8087|0.0.0.0:${PORT_FLIGHT}|g" "${OUTPUT}"  
    fi  
    if [ "${PORT_META_BIND}" != "8088" ]; then  
        sed -i "s|${NODE_IP}:8088|${NODE_IP}:${PORT_META_BIND}|g" "${OUTPUT}"  
    fi  
    if [ "${PORT_META_HTTP}" != "8091" ]; then  
        sed -i "s|${NODE_IP}:8091|${NODE_IP}:${PORT_META_HTTP}|g" "${OUTPUT}"  
    fi  
    if [ "${PORT_META_RPC}" != "8092" ]; then  
        sed -i "s|${NODE_IP}:8092|${NODE_IP}:${PORT_META_RPC}|g" "${OUTPUT}"  
    fi  
    if [ "${PORT_STORE_INGEST}" != "8400" ]; then  
        sed -i "s|${NODE_IP}:8400|${NODE_IP}:${PORT_STORE_INGEST}|g" "${OUTPUT}"  
    fi  
    if [ "${PORT_STORE_SELECT}" != "8401" ]; then  
        sed -i "s|${NODE_IP}:8401|${NODE_IP}:${PORT_STORE_SELECT}|g" "${OUTPUT}"  
    fi  
    if [ "${PORT_GOSSIP_META}" != "8010" ]; then  
        sed -i "s|meta-bind-port = 8010|meta-bind-port = ${PORT_GOSSIP_META}|" "${OUTPUT}"  
    fi  
    if [ "${PORT_GOSSIP_STORE}" != "8011" ]; then  
        sed -i "s|store-bind-port = 8011|store-bind-port = ${PORT_GOSSIP_STORE}|" "${OUTPUT}"  
    fi  
    if [ "${PORT_GOSSIP_SQL}" != "8012" ]; then  
        sed -i "s|sql-bind-port = 8012|sql-bind-port = ${PORT_GOSSIP_SQL}|" "${OUTPUT}"  
    fi  
  
    log_info "配置文件已生成: ${OUTPUT} (IP=${NODE_IP}, MODE=${DEPLOY_MODE})"  
}  
  
#===============================================================================  
# 步骤1: 创建安装路径  
#===============================================================================  
if should_run 1; then  
    log_info "========== 步骤1: 创建安装路径 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "在节点 ${NODE} 创建目录 ${INSTALL_PATH}"  
        ssh root@${NODE} "mkdir -p ${INSTALL_PATH}"  
        check_result "节点 ${NODE} 创建目录"  
    done  
fi  
  
#===============================================================================  
# 步骤2: 拷贝压缩包并解压  
#===============================================================================  
if should_run 2; then  
    log_info "========== 步骤2: 拷贝压缩包并解压 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "SCP 压缩包到节点 ${NODE}"  
        scp "${SCRIPT_DIR}/${ZIP_FILE}" root@${NODE}:${INSTALL_PATH}/  
        check_result "SCP 到 ${NODE}"  
  
        log_info "在节点 ${NODE} 解压"  
        ssh root@${NODE} "cd ${INSTALL_PATH} && unzip ${ZIP_FILE}"  
        check_result "节点 ${NODE} 解压"  
    done  
fi  
  
#===============================================================================  
# 步骤3: 生成并分发配置文件  
#===============================================================================  
if should_run 3; then  
    log_info "========== 步骤3: 生成并分发配置文件 =========="  
    for NODE in "${NODES[@]}"; do  
        TMP_CONF="/tmp/opengemini.conf.${NODE}"  
        generate_conf "${NODE}" "${TMP_CONF}"  
  
        log_info "验证关键配置项 (${NODE}):"  
        echo "  meta-join: $(grep 'meta-join' ${TMP_CONF})"  
        echo "  ha-policy: $(grep 'ha-policy' ${TMP_CONF} | grep -v '#')"  
        echo "  meta dir: $(grep '  dir = ' ${TMP_CONF} | head -1)"  
        echo "  store-data-dir: $(grep 'store-data-dir' ${TMP_CONF})"  
        echo "  store-wal-dir: $(grep 'store-wal-dir' ${TMP_CONF})"  
        echo "  logging path: $(grep '  path = ' ${TMP_CONF} | head -1)"  
        echo "  gossip enabled: $(grep -A1 '^\[gossip\]' ${TMP_CONF} | grep enabled)"  
        echo "  subscriber: $(grep -A1 '^\[subscriber\]' ${TMP_CONF} | grep enabled)"  
        echo "  http bind: $(grep 'bind-address = "0.0.0.0' ${TMP_CONF})"  
  
        log_info "SCP 配置文件到节点 ${NODE}"  
        scp "${TMP_CONF}" root@${NODE}:${INSTALL_PATH}/etc/opengemini.conf  
        check_result "节点 ${NODE} 分发配置文件"  
        rm -f "${TMP_CONF}"  
    done  
fi  
  
#===============================================================================  
# 步骤4: 配置 systemd 服务  
#===============================================================================  
if should_run 4; then  
    log_info "========== 步骤4: 配置 systemd 服务 =========="  
    for NODE in "${NODES[@]}"; do  
        for SVC in ts-meta.service ts-sql.service ts-store.service; do  
            log_info "处理 ${SVC} -> 节点 ${NODE}"  
            TMP_SVC="/tmp/${SVC}.${NODE}"  
            sed "s|\\\$install_path|${INSTALL_PATH}|g" "${SCRIPT_DIR}/${SVC}" > "${TMP_SVC}"  
            scp "${TMP_SVC}" root@${NODE}:/usr/lib/systemd/system/${SVC}  
            rm -f "${TMP_SVC}"  
            check_result "${SVC} -> ${NODE}"  
        done  
  
        log_info "节点 ${NODE} daemon-reload"  
        ssh root@${NODE} "systemctl daemon-reload"  
        check_result "节点 ${NODE} daemon-reload"  
    done  
fi  
  
#===============================================================================  
# 步骤5: 配置环境变量  
#===============================================================================  
if should_run 5; then  
    log_info "========== 步骤5: 配置环境变量 =========="  
    OPENGEMINI_SH="/tmp/opengemini.sh"  
    echo '#!/bin/bash' > "${OPENGEMINI_SH}"  
    echo "export OPENGEMINI_HOME=\"${INSTALL_PATH}\"" >> "${OPENGEMINI_SH}"  
    echo 'export PATH="${OPENGEMINI_HOME}/usr/bin:${PATH}"' >> "${OPENGEMINI_SH}"  
  
    log_info "本地生成 opengemini.sh 内容:"  
    cat "${OPENGEMINI_SH}"  
  
    for NODE in "${NODES[@]}"; do  
        log_info "拷贝 opengemini.sh 到节点 ${NODE}:/etc/profile.d/"  
        scp "${OPENGEMINI_SH}" root@${NODE}:/etc/profile.d/opengemini.sh  
        check_result "节点 ${NODE} 配置环境变量"  
    done  
    rm -f "${OPENGEMINI_SH}"  
fi  
  
#===============================================================================  
# 步骤6: 启动服务  
#===============================================================================  
if should_run 6; then  
    log_info "========== 步骤6: 启动服务 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "启动节点 ${NODE} 的 ts-meta ts-store ts-sql"  
        ssh root@${NODE} "systemctl restart ts-meta && sleep 2 && systemctl restart ts-store && sleep 2 && systemctl restart ts-sql"  
        check_result "节点 ${NODE} 启动服务"  
  
        sleep 3  
        log_info "检查节点 ${NODE} 服务状态"  
        ssh root@${NODE} "systemctl is-active ts-meta ts-store ts-sql"  
        check_result "节点 ${NODE} 服务状态"  
    done  
fi  
  
#===============================================================================  
# 步骤7: 创建管理员用户（鉴权未开启）  
#===============================================================================  
if should_run 7; then  
    log_info "========== 步骤7: 创建管理员用户 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "在节点 ${NODE} 创建管理员 ${DB_USER}"  
        echo "curl -s -XPOST \"http://${NODE}:${PORT_HTTP}/query\" --data-urlencode \"q=CREATE USER \\\"${DB_USER}\\\" WITH PASSWORD '${DB_PASS}' WITH ALL PRIVILEGES\""  
        RESPONSE=$(curl -s -XPOST "http://${NODE}:${PORT_HTTP}/query" --data-urlencode "q=CREATE USER \"${DB_USER}\" WITH PASSWORD '${DB_PASS}' WITH ALL PRIVILEGES")  
        echo "  响应: ${RESPONSE}"  
        if echo "${RESPONSE}" | grep -q '"error"'; then  
            if echo "${RESPONSE}" | grep -q "already exists"; then  
                log_warn "节点 ${NODE} 用户已存在，跳过"  
            else  
                log_error "节点 ${NODE} 创建用户失败: ${RESPONSE}"  
                exit 1  
            fi  
        else  
            log_info "节点 ${NODE} 创建用户成功"  
        fi  
    done  
fi  
  
#===============================================================================  
# 步骤8: 开启鉴权并重启  
#===============================================================================  
if should_run 8; then  
    log_info "========== 步骤8: 开启鉴权并重启 =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "拉取节点 ${NODE} 配置文件"  
        TMP_AUTH="/tmp/opengemini.conf.auth.${NODE}"  
        scp root@${NODE}:${INSTALL_PATH}/etc/opengemini.conf "${TMP_AUTH}"  
  
        log_info "开启 auth-enabled"  
        sed -i 's|# auth-enabled = false|auth-enabled = true|g' "${TMP_AUTH}"  
  
        log_info "验证鉴权配置:"  
        grep -n "auth-enabled" "${TMP_AUTH}" | grep -v "#"  
  
        scp "${TMP_AUTH}" root@${NODE}:${INSTALL_PATH}/etc/opengemini.conf  
        rm -f "${TMP_AUTH}"  
  
        log_info "重启节点 ${NODE} 所有服务"  
        ssh root@${NODE} "systemctl restart ts-meta && sleep 2 && systemctl restart ts-store && sleep 2 && systemctl restart ts-sql"  
        check_result "节点 ${NODE} 重启"  
  
        sleep 5  
  
        log_info "验证节点 ${NODE} 鉴权是否生效"  
        RESPONSE=$(curl -s -G "http://${NODE}:${PORT_HTTP}/query" --data-urlencode "q=SHOW DATABASES" || true)  
        echo "  未认证请求响应: ${RESPONSE}"  
        if echo "${RESPONSE}" | grep -q "authentication"; then  
            log_info "节点 ${NODE} 鉴权已生效"  
        else  
            log_warn "节点 ${NODE} 鉴权可能未生效，请检查"  
        fi  
    done  
fi  
  
#===============================================================================  
# 步骤9: 创建数据库  
#===============================================================================  
if should_run 9; then  
    log_info "========== 步骤9: 创建数据库 slurm_profile =========="  
    for NODE in "${NODES[@]}"; do  
        log_info "在节点 ${NODE} 创建数据库"  
        RESPONSE=$(curl -s -XPOST "http://${NODE}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "q=CREATE DATABASE slurm_profile")  
        echo "  响应: ${RESPONSE}"  
        check_result "节点 ${NODE} 创建数据库"  
    done  
fi  
  
#===============================================================================  
# 步骤10: 创建 Measurements  
#===============================================================================  

if should_run 10; then  
    log_info "========== 步骤10: 创建 Measurements =========="  
  
    # 确定哪些节点需要创建表  
    declare -a MST_NODES=()  
    if [ "${CREATE_MEASUREMENTS_PRIMARY}" == "true" ]; then  
        MST_NODES+=("${PRIMARY_IP}")  
        log_info "主节点 ${PRIMARY_IP} 将创建表"  
    else  
        log_info "主节点 ${PRIMARY_IP} 跳过创建表"  
    fi  
    if [ "${DEPLOY_MODE}" == "dual" ]; then  
        if [ "${CREATE_MEASUREMENTS_BACKUP}" == "true" ]; then  
            MST_NODES+=("${BACKUP_IP}")  
            log_info "备节点 ${BACKUP_IP} 将创建表"  
        else  
            log_info "备节点 ${BACKUP_IP} 跳过创建表"  
        fi  
    fi  
  
    if [ ${#MST_NODES[@]} -eq 0 ]; then  
        log_info "所有节点均跳过创建表"  
    else  
        declare -a MEASUREMENTS  
        MEASUREMENTS[0]='CREATE MEASUREMENT Stepd (jobid TAG, step TAG, username TAG, interval_time FLOAT64, stepcpu FLOAT64, stepcpuave FLOAT64, stepmem FLOAT64, steppages FLOAT64, stepvmem FLOAT64, stepdcuutil FLOAT64, stepdcumem FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, jobid, step, time PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[1]='CREATE MEASUREMENT Event (jobid TAG, step TAG, "type" TAG, username TAG, cputhreshold FLOAT64, gresthreshold FLOAT64, "end" FLOAT64, "start" FLOAT64, stepcpu FLOAT64, stepmem FLOAT64, steppages FLOAT64, stepvmem FLOAT64, stepdcumem FLOAT64, stepdcuutil FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, "type", jobid, step, time PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[2]='CREATE MEASUREMENT Apptype (jobid TAG, step TAG, username TAG, apptype_cli STRING, apptype_step STRING, cputime STRING) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, jobid, step, time PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[3]='CREATE MEASUREMENT CPUTime (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[4]='CREATE MEASUREMENT CPUFrequency (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[5]='CREATE MEASUREMENT CPUUtilization (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[6]='CREATE MEASUREMENT GPUMemMB (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[7]='CREATE MEASUREMENT GPUUtilization (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[8]='CREATE MEASUREMENT Pages (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[9]='CREATE MEASUREMENT RSS (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[10]='CREATE MEASUREMENT ReadMB (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[11]='CREATE MEASUREMENT VMSize (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
        MEASUREMENTS[12]='CREATE MEASUREMENT WriteMB (host TAG, job TAG, step TAG, "task" TAG, username TAG, value FLOAT64) WITH ENGINETYPE = COLUMNSTORE PRIMARYKEY username SORTKEY username, host, job, step, "task" PROPERTY primaryKeyType="cluster"'  
  
        for NODE in "${MST_NODES[@]}"; do  
            log_info "在节点 ${NODE} 创建所有 Measurements"  
            for i in "${!MEASUREMENTS[@]}"; do  
                MST="${MEASUREMENTS[$i]}"  
                MST_NAME=$(echo "${MST}" | awk '{print $3}')  
                log_info "  创建 ${MST_NAME} ..."  
                RESPONSE=$(curl -s -XPOST "http://${NODE}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=${MST}")  
                echo "    响应: ${RESPONSE}"  
                if echo "${RESPONSE}" | grep -q '"error"'; then  
                    log_error "  节点 ${NODE} 创建 ${MST_NAME} 失败"  
                else  
                    log_info "  节点 ${NODE} 创建 ${MST_NAME} 成功"  
                fi  
            done  
        done  
    fi  
fi  

#===============================================================================  
# 步骤11: 创建订阅 (仅双节点模式)  
#===============================================================================  
if should_run 11; then  
    if [ "${DEPLOY_MODE}" == "dual" ]; then  
        log_info "========== 步骤11: 创建订阅 (主 -> 备) =========="  
        SUBSCRIPTION_SQL="CREATE SUBSCRIPTION \"send_to_backup\" ON \"slurm_profile\".\"autogen\" DESTINATIONS ALL 'http://${DB_USER}:${DB_PASS}@${BACKUP_IP}:${PORT_HTTP}'"  
        log_info "执行: ${SUBSCRIPTION_SQL}"  
        RESPONSE=$(curl -s -XPOST "http://${PRIMARY_IP}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "q=${SUBSCRIPTION_SQL}")  
        echo "  响应: ${RESPONSE}"  
        if echo "${RESPONSE}" | grep -q '"error"'; then  
            log_error "创建订阅失败"  
            exit 1  
        fi  
        log_info "创建订阅成功"  
  
        log_info "验证订阅"  
        RESPONSE=$(curl -s -XPOST "http://${PRIMARY_IP}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "q=SHOW SUBSCRIPTIONS")  
        echo "  订阅列表: ${RESPONSE}"  
    else  
        log_info "========== 步骤11: 跳过 (单节点模式无需订阅) =========="  
    fi  
fi  
  
#===============================================================================  
# 步骤12: 安装验证  
#===============================================================================  
if should_run 12; then  
    log_info "========== 步骤12: 安装验证 =========="  
  
    TIMESTAMP=$(date +%s)000000000  
    TEST_DATA="install_test,host=testnode value=1 ${TIMESTAMP}"  
  
    log_info "在主节点 ${PRIMARY_IP} 写入测试数据"  
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "http://${PRIMARY_IP}:${PORT_HTTP}/write?db=slurm_profile" -u "${DB_USER}:${DB_PASS}" --data-binary "${TEST_DATA}" || true)  
    echo "  HTTP 状态码: ${HTTP_CODE}"  
    if [ "${HTTP_CODE}" == "204" ]; then  
        log_info "写入测试数据成功"  
    else  
        log_error "写入测试数据失败，HTTP 状态码: ${HTTP_CODE}"  
        exit 1  
    fi  
  
    sleep 3  
  
    log_info "在主节点 ${PRIMARY_IP} 查询测试数据"  
    RESPONSE=$(curl -s -G "http://${PRIMARY_IP}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=SELECT * FROM install_test LIMIT 1")  
    echo "  查询结果: ${RESPONSE}"  
    if echo "${RESPONSE}" | grep -q "testnode"; then  
        log_info "主节点数据验证通过"  
    else  
        log_error "主节点数据验证失败"  
        exit 1  
    fi  
  
    if [ "${DEPLOY_MODE}" == "dual" ]; then  
        log_info "等待订阅同步..."  
        sleep 5  
  
        log_info "在备节点 ${BACKUP_IP} 查询测试数据"  
        RESPONSE=$(curl -s -G "http://${BACKUP_IP}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=SELECT * FROM install_test LIMIT 1")  
        echo "  查询结果: ${RESPONSE}"  
        if echo "${RESPONSE}" | grep -q "testnode"; then  
            log_info "备节点数据验证通过 - 订阅同步正常"  
        else  
            log_error "备节点数据验证失败 - 订阅同步可能存在问题"  
            exit 1  
        fi  
    fi  
  
    log_info "清理测试表"  
    for NODE in "${NODES[@]}"; do  
        curl -s -XPOST "http://${NODE}:${PORT_HTTP}/query" -u "${DB_USER}:${DB_PASS}" --data-urlencode "db=slurm_profile" --data-urlencode "q=DROP MEASUREMENT install_test" > /dev/null 2>&1  
    done  
    log_info "测试表已清理"  
fi  
  
#===============================================================================  
echo ""  
log_info "============================================="  
log_info "  openGemini 安装部署完成"  
log_info "============================================="  
log_info "  部署模式: ${DEPLOY_MODE}"  
log_info "  主节点: ${PRIMARY_IP}"  
if [ "${DEPLOY_MODE}" == "dual" ]; then  
    log_info "  备节点: ${BACKUP_IP}"  
fi  
log_info "  安装路径: ${INSTALL_PATH}"  
log_info "  数据库: slurm_profile"  
log_info "  管理员: ${DB_USER}"  
log_info "  HTTP 端口: ${PORT_HTTP}"  
if [ "${DEPLOY_MODE}" == "dual" ]; then  
    log_info "  订阅: send_to_backup (主 -> 备)"  
fi  
log_info "============================================="