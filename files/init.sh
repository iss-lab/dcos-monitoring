#!/usr/bin/env bash

set -o errexit -o pipefail

[ ! -z ${PROMETHEUS_YML_BASE64} ] && \
  rm -f ${MESOS_SANDBOX}/scheduler/prometheus.yml && \
  echo "${PROMETHEUS_YML_BASE64}" | base64 -d > ${MESOS_SANDBOX}/scheduler/prometheus.yml
[ ! -z ${LDAP_TOML_MUSTACHE_BASE64} ] && \
  rm -f ${MESOS_SANDBOX}/scheduler/ldap.toml.mustache && \
  echo "${LDAP_TOML_MUSTACHE_BASE64}" | base64 -d > ${MESOS_SANDBOX}/scheduler/ldap.toml.mustache
[ ! -z ${GRAFANA_INI_MUSTACHE_BASE64} ] && \
  rm -f ${MESOS_SANDBOX}/scheduler/grafana.ini.mustache && \
  echo "${GRAFANA_INI_MUSTACHE_BASE64}" | base64 -d > ${MESOS_SANDBOX}/scheduler/grafana.ini.mustache

# Render the templates.
GRAFANA_ADMIN_USERNAME=${GRAFANA_ADMIN_CREDENTIALS_USERNAME_VALUE:-"admin"}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_CREDENTIALS_PASSWORD_VALUE:-"admin"}
GRAFANA_AUTH=$(echo -n "${GRAFANA_ADMIN_USERNAME}:${GRAFANA_ADMIN_PASSWORD}" | base64 --wrap 0)

USER_DIRECTIVE=""
if [ "$(id -u)" -eq 0 ]; then
USER_DIRECTIVE="user root;"
fi

DNS_FRAMEWORK_NAME=$(echo "${SERVICE_NAME}" | sed 's/\///g')

export GRAFANA_AUTH DNS_FRAMEWORK_NAME USER_DIRECTIVE

ENV_VARS="\${MESOS_SANDBOX},\${PORT_PROXY},\${PORT_API},\${SERVICE_NAME},\${GRAFANA_AUTH},\${DNS_FRAMEWORK_NAME},\${USER_DIRECTIVE}"

mkdir -p ${MESOS_SANDBOX}/nginx

envsubst "${ENV_VARS}" < "${MESOS_SANDBOX}/nginx.conf.tmpl" > "${MESOS_SANDBOX}/nginx/nginx.conf"

# Start the proxy.
nginx -c "${MESOS_SANDBOX}/nginx/nginx.conf"

LD_LIBRARY_PATH="${MESOS_SANDBOX}/libmesos-bundle/lib:${LD_LIBRARY_PATH}"
MESOS_NATIVE_JAVA_LIBRARY=$(ls "${MESOS_SANDBOX}"/libmesos-bundle/lib/libmesos-*.so)
JAVA_HOME=$(ls -d "${MESOS_SANDBOX}"/jdk*/)
JAVA_HOME="${JAVA_HOME%/}"
PATH=$(ls -d "${JAVA_HOME}/bin"):"${PATH}"
JAVA_OPTS="-Xms256M -Xmx512M -XX:-HeapDumpOnOutOfMemoryError"

export \
  LD_LIBRARY_PATH \
  MESOS_NATIVE_JAVA_LIBRARY \
  JAVA_HOME \
  PATH \
  JAVA_OPTS

"${MESOS_SANDBOX}/bootstrap" -resolve=false -template=false

"${MESOS_SANDBOX}/scheduler/bin/scheduler" "${MESOS_SANDBOX}/scheduler/svc.yml" &

# Terminate the script if any of the background process terminates.
wait -n
