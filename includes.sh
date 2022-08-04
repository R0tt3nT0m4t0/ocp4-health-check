#!/usr/bin/env bash
# Openshift 4 Health Check Report Generator 
# Includes file
# Author: jumedina@redhat.com 
# 

# Enable/Disable sections as needed to add to the Health Check 
# Or comment out in the Main the function calls if need 
# to disable a whole section.

include_executive_summary=true

declare -A commons_includes=( 
   [versions]=true
   [cluster_operators_degraded]=true
   [cluster_operators_unavailable]=true
   [cluster_status_failing_conditions]=true 
   [cluster_events_abnormal]=true 
   [cluster_nodes_status]=true 
   [cluster_console_status]=true 
   [cluster_api_status]=true 
)
declare -A nodes_includes=(
   [cluster_nodes_status]=true
   [cluster_nodes_conditions]=true
   [nodes_capacity]=true
   [customresourcedefinitions]=true
   [clusterresourcequotas]=true
   [clusterserviceversions]=true
) 
declare -A machine_includes=(
   [list_machines]=true
   [list_machinesets]=true
   [machine_configs]=true
   [machine_configs_pools]=true
   [machineautoscaler]=true
   [clusterautoscaler]=true
   [machinehealthcheck]=true
)
declare -A etcd_includes=(
   [list_etcd_pods]=true
   [member_list]=true
   [endpoint_status]=true
   [endpoint_health]=true
)
declare -A pods_includes=(
   [list_failing_pods]=true
   [constantly_restarted_pods]=true
   [long_running_pods]=true
   [poddisruptionbudget]=true
   [pods_in_default]=true
   [pods_per_node]=true
) 
declare -A security_includes=(
   [pending_csr]=true
   [identities]=true
   [identities_grants]=true
   [rolebindings]=true
   [clusterrolebindings]=true
   [kubeadmin_secret]=true
   [identity_providers]=true
   [authentications]=true
   [kubeletconfig]=true
   [subscriptions]=true
   [webhooks]=true
   [api_versions]=true
)
declare -A storage_includes=(
   [pv_status]=true
   [pvc_status]=true
   [storage_classes]=true
   [quotas]=true
   [volumeSnapshot]=true
   [csidrivers]=true
   [csinodes]=true
   [featuregate]=true
   [horizontalpodautoscalers]=true
)
declare -A logging_includes=(
   [logging_resources]=true
)
declare -A performance_includes=(
   [nodes_memory]=true
   [nodes_cpu]=true
   [pods_memory]=true
   [pods_cpu]=true
)
declare -A monitoring_includes=(
   [prometheus]=true 
   [prometheus_rules]=true
   [servicemonitors]=true 
   [podmonitors]=true 
   [alertmanagers]=true 
   [agents]=true 
)
declare -A network_includes=(
   [enabled_network]=true
   [networkpolicies]=true
   [clusternetworks]=true
   [hostsubnet]=true
   [proxy]=true
   [endpoints]=true 
   [route]=true
   [egressnetworkpolicy]=true
   [ingresscontrollers]=true
   [ingresses]=true
   [ingress_controler_pods]=true
   [mtu_size]=true
   [podnetworkconnectivitycheck]=true
)
declare -A operators_includes=(
   [operators_degraded]=true
   [operators_unavailable]=true
   [cluster_services]=true
   [operatorgroups]=true
   [operatorsources]=true
)
declare -A mesh_includes=(
   [serviceMeshControlPlane]=true
   [serviceMeshMember]=true
   [serviceMeshMemberRoll]=true
)
declare -A application_includes=(
   [deploy_demo_app]=true 
   [non_ready_deployments]=true
   [non_available_deployments]=true
   [inactive_projects]=true
   [failed_builds]=true
)

