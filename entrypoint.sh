#!/bin/sh
readonly token_filepath=/var/run/secrets/kubernetes.io/serviceaccount/token
readonly cacert_filepath=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

join_host_port() (
    host=$1
    shift
    port=$1
    shift
    case "$host" in
        (*:*)
            printf '[%s]:%s' "$host" "$port"
            ;;
        (*)
            printf %s:%s "$host" "$port"
            ;;
    esac
)

is_hcloud_provided() (
    provider_id=$1
    shift
    [ "$provider_id" != "${provider_id#hcloud://}" ]
)

get_hcloud_server_id_from_node_provider_id() (
    provider_id=$1
    shift
    printf %s "${provider_id#hcloud://}"
)

if [ -z "$KUBE_NODE_NAME" ] ; then
    printf "Environment variable KUBE_NODE_NAME is missing or empty, skipping configuration for Kubernetes.\n" >&2
    exec "$@"
fi
if [ -z "$KUBERNETES_SERVICE_HOST" ] || [ -z "$KUBERNETES_SERVICE_PORT" ] ; then
    printf "At least one of environment variable KUBERNETES_SERVICE_HOST and KUBERNETES_SERVICE_PORT is missing or empty, skipping configuration for Kubernetes.\n" >&2
    exec "$@"
fi
token=`cat "$token_filepath"`
if [ $? != 0 ] ; then
    printf "Could not read token from %s, skipping configuration for Kubernetes.\n" "$token_filepath" >&2
    exec "$@"
fi
kubernetes_service_addr="https://$(join_host_port "$KUBERNETES_SERVICE_HOST" "$KUBERNETES_SERVICE_PORT")"
out="$(curl --cacert "$cacert_filepath" -H "Authorization: Bearer $token" -X GET --no-progress-meter -k -w '%{response_code}\n' "$kubernetes_service_addr/api/v1/nodes/$KUBE_NODE_NAME?pretty=false")"
if [ "$?" != 0 ] ; then
    printf "Could not request the Kubernetes API, skipping configuration for Kubernetes.\n" >&2
    exec "$@"
fi
response_code=`printf %s "$out" | tail -n 1`
response_body=`printf %s "$out" | head -n -1`
if [ "$response_code" != 200 ] ; then
    printf '%s\n' "$response_body" >&2
    printf "Expected HTTP response status code 200 from the Kubernetes API but got %s, skipping configuration for Kubernetes.\n" "$response_code" >&2
    exec "$@"
fi
node=$response_body
node_provider_id=`printf %s "$node" | jq -r '.spec?.providerID? // ""'`
node_topology_region=`printf %s "$node" | jq -r '.metadata?.labels?."topology.kubernetes.io/region"? // ""'`
if ! is_hcloud_provided "$node_provider_id" ; then
    exec "$@"
fi
[ -n "${node_provider_id}" ] && export HCLOUD_SERVER_ID="$(get_hcloud_server_id_from_node_provider_id "$node_provider_id")"
[ -n "${node_topology_region}" ] && export HCLOUD_SERVER_LOCATION="${node_topology_region}"
exec "$@"
