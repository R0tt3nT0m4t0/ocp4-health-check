#!/usr/bin/env bash
# Openshift 4 Health Check Report Generator 
# Author: jumedina@redhat.com 

# Global Variables 

if [ -z ${1} ]
then 
   echo "A short customer name is required"
   exit 
fi 
customer=${1}
adoc="pdf/report.adoc"
namespaces=$(oc get namespaces --no-headers | awk '{print $1}')
cv=$(oc version | grep Server | awk '{print $3}' | sed -e 's/.[0-9][0-9]$//g')  # cluster version  

source includes.sh 

# Functions 

environment_setup(){
   # Verify oc command 
   if [ ! command -v oc &> /dev/null ] 
   then 
      echo "Command oc could not be found!"
      exit 
   fi 
   # Verify jq command 
   if [ ! command -v jq &> /dev/null ]
   then 
      echo "Command jq could not be found!"
      exit 
   fi 
   # Delete old report
   rm ${adoc}
   # Initialize report 
   echo ":author: Red Hat Consulting" >> ${adoc}
   echo ":toc:" >> ${adoc}
   echo ":numbered:" >> ${adoc}
   echo ":doctype: book" >> ${adoc}
   echo ":imagesdir: ../images" >> ${adoc}
   echo ":stylesdir: ../styles/" >> ${adoc}
   echo ":listing-caption: Listing" >> ${adoc}
   echo ":pdf-page-size: A4" >> ${adoc}
   echo ":pdf-style: redhat" >> ${adoc}
   echo ":pdf-stylesdir: styles/" >> ${adoc}
   echo ":pdf-fontsdir: fonts/" >> ${adoc}
   echo "" >> ${adoc}
   echo "= Openshift 4 Health Check Report" >> ${adoc}
   echo "" >> ${adoc}
}

generate_pdf(){
   report="${customer}_HealthCheck_Report.pdf"
   if [[ -d pdf ]]
   then 
      cd pdf
      asciidoctor-pdf --verbose -r asciidoctor-diagram --out-file "../${report}" report.adoc
   else
      echo "The `pdf` directory couldn't be found!"
      exit 
   fi
}

title(){
   echo "== ${1}" >> ${adoc}
   echo "" >> ${adoc}
}

sub(){
   echo "=== ${1}" >> ${adoc}
   echo "" >> ${adoc}
}

code(){ 
   echo "----" >> ${adoc} 
}

quote(){
   echo ".${1}" >> ${adoc} 
   echo "" >> ${adoc} 
}

link(){
   echo "" >> ${adoc} 
   echo "${1}[Reference Documentation]" >> ${adoc} 
   echo "" >> ${adoc} 
}

commons(){
   title "Commons"

   versions(){
      sub "Versions"
      quote "Red Hat OpenShift Container Platform Life Cycle Policy"
      link "https://access.redhat.com/support/policy/updates/openshift"
      code 
      oc version >> ${adoc}
      code 
   }

   componentstatuses(){
      sub "Components status"
      quote "ComponentStatus (and ComponentStatusList) holds the cluster validation info. Deprecated: This API is deprecated in v1.19+"
      link "https://docs.openshift.com/container-platform/${cv}/rest_api/metadata_apis/componentstatus-v1.html"
      code
      oc get componentstatuses 2>/dev/null >> ${adoc}
      code
   }

   cluster_status_failing_conditions(){
      sub "Cluster Status Conditions"
      quote "ClusterOperatorStatusCondition represents the state of the operator’s managed and monitored components."
      link "https://docs.openshift.com/container-platform/${cv}/installing/validating-an-installation.html#getting-cluster-version-and-update-details_validating-an-installation"
      code 
      if [ "True" == $(oc get clusterversion -o=jsonpath='{range .items[0].status.conditions[?(@.type=="Failing")]}{.status}') ]
      then
         oc get clusterversion -o=json | jq '.items[].status.conditions' >> ${adoc}
      fi
      code 
   }

   cluster_events_abnormal(){
      sub "Cluster Abnormal Events"
      quote "Events are records of important life-cycle information and are useful for monitoring and troubleshooting resource scheduling, creation, and deletion issues."
      link "https://docs.openshift.com/container-platform/${ns}/virt/logging_events_monitoring/virt-events.html#virt-about-vm-events_virt-events"
      code 
      oc get events --field-selector type!=Normal -A | awk '{print $1,$3,$4,$5}' | sort | uniq >> ${adoc}
      code 
   }

   cluster_api_status(){
      sub "Cluster API Server Status"
      api_url=$(oc whoami --show-server)
      code 
         curl -k ${api_url} 2>/dev/null | grep 403 >/dev/null 
         if [ $? != 0 ]
         then 
            echo "Cluster API Server Status: FAILED" >> ${adoc}
         fi 
      code 
   }

   cluster_console_status(){
      sub "Cluster Console Status"
      console_url=$(oc whoami --show-console)
      code 
         curl -k ${console_url} 2>/dev/null | grep "<title>Red Hat OpenShift Container Platform</title>" >/dev/null 
         if [ $? != 0 ]
         then 
            echo "Cluster Console Status: FAILED" >> ${adoc}
         fi 
      code 
   }

   # Includes 
   if ${commons_includes[versions]};then versions; fi 
   if ${commons_includes[componentstatuses]};then componentstatuses; fi 
   if ${commons_includes[cluster_status_failing_conditions]};then cluster_status_failing_conditions; fi 
   if ${commons_includes[cluster_events_abnormal]};then cluster_events_abnormal; fi 
   if ${commons_includes[cluster_api_status]};then cluster_api_status; fi 
   if ${commons_includes[cluster_console_status]};then cluster_console_status; fi 
}

nodes(){
   title "nodes"

   cluster_nodes_status(){
      sub "Cluster Failing Nodes"
      code 
      oc get nodes --no-headers | awk '$2 != "Ready"' >> ${adoc}
      code 
   }

   cluster_nodes_conditions(){
      sub "Cluster Node Conditions"
      labels=(master worker infra)
      for type in ${labels[@]}
      do
         echo "==== ${type} Nodes" >> ${adoc}
         for node in $(oc get nodes --no-headers | sed 's/,/ /g' | awk '{print $1, $3}' | grep ${type} | awk '{print $1}')
         do
            echo "**${node}**" >> ${adoc}
            code
            #oc get node ${node} -o json | jq -r '.status.conditions[] | {type,status,reason}' >> ${adoc}
            #oc describe node $node | grep "MemoryPressure|DiskPressure|PIDPressure" | grep -w True >> ${adoc}
            oc get node ${node} -o json | \
               jq -cr '.status.conditions[] | {type,status,reason}' | \
               tr -d '{}"' | \
               sed 's/type://g; s/status://g; s/reason://g; s/,/ /g' | \
               grep 'Pressure' >> ${adoc}
            code
         done
      done
   }

   nodes_capacity(){
      sub "Nodes Capacity"
      echo "[%header,cols='3,1,1,1,2,2,1']" >> ${adoc}
      echo "|===" >> ${adoc}
      echo "|NODE|TYPE|OS|CPU|MEM|STORAGE|PODS" >> ${adoc}
      labels=(master worker infra)
      for type in ${labels[@]}
      do
         for node in $(oc get nodes --no-headers | sed 's/,/ /g' | awk '{print $1, $3}' | grep ${type} | awk '{print $1}')
         do
            oc describe node ${node} | grep "OS Image:" | grep -q CoreOS >/dev/null
            if [ $? -eq 0 ]
            then 
               os="CoreOS"
            else
               os="RHEL"
            fi
            capacity=($(oc describe node ${node} | grep -A 6 "Capacity:" | grep "cpu\|memory\|storage\|pods" | awk '{print $NF}'))
            echo "|${node}|${type}|${os}|$(echo ${capacity[@]} | sed 's/ /|/g')" >> ${adoc}
         done
      done 
      echo "|===" >> ${adoc}
   }

   customresourcedefinitions(){
      sub "Custom Resource Definitions"
      quote "A custom resource definition (CRD) object defines a new, unique object type, called a kind, in the cluster and lets the Kubernetes API server handle its entire lifecycle."
      link "https://docs.openshift.com/container-platform/${cv}/operators/understanding/crds/crd-extending-api-with-crds.html"
      code 
      oc get customresourcedefinitions --no-headers | awk '{print $1}' >> ${adoc}
      code 
   }

   clusterresourcequotas(){
      sub "Cluster Resource Quotas"
      quote "A multi-project quota, defined by a ClusterResourceQuota object, allows quotas to be shared across multiple projects."
      link "https://docs.openshift.com/container-platform/${cv}/applications/quotas/quotas-setting-across-multiple-projects.html"
      code 
      oc get clusterresourcequotas.quota.openshift.io -A 2>/dev/null >> ${adoc}
      code 
   }

   clusterserviceversions(){
      sub "Cluster Service Versions"
      quote "A multi-project quota, defined by a ClusterResourceQuota object, allows quotas to be shared across multiple projects."
      link "https://docs.openshift.com/container-platform/${cv}/applications/quotas/quotas-setting-across-multiple-projects.html"
      code
      oc get clusterserviceversions.operators.coreos.com -A 2>/dev/null >> ${adoc}
      code 
   }

   # Includes 
   if ${nodes_includes[cluster_nodes_status]};then cluster_nodes_status; fi 
   if ${nodes_includes[cluster_nodes_conditions]};then cluster_nodes_conditions; fi 
   if ${nodes_includes[nodes_capacity]};then nodes_capacity; fi 
   if ${nodes_includes[customresourcedefinitions]};then customresourcedefinitions; fi 
   if ${nodes_includes[clusterresourcequotas]};then clusterresourcequotas; fi 
   if ${nodes_includes[clusterserviceversions]};then clusterserviceversions; fi 

} 

machines(){
   title "Machines"

   list_machines(){
      sub "Machine Info"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      code 
      oc get machines -A 2>/dev/null >> ${adoc}
      code 
   }

   list_machinesets(){
      sub "Machinesets Info"
            quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      code 
      oc get machinesets -A 2>/dev/null >> ${adoc}
      code 
   }

   machine_configs(){
      sub "Machine Configs"
         quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      code 
      oc get nodes machineconfig 2>/dev/null >> ${adoc}
      code 
   }

   machine_configs_pools(){
      sub "Machine Configs"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      code 
      oc get nodes machineconfigpools 2>/dev/null >> ${adoc}
      code 
   }

   machineautoscaler(){
      sub "Machine Auto Scalers"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      code 
      oc get machineautoscaler -A 2>/dev/null >> ${adoc} 
      code 
   }

   clusterautoscaler(){
      sub "Cluster Auto Scalers"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      code 
      oc get clusterautoscaler -A 2>/dev/null >> ${adoc} 
      code 
   }

   machinehealthcheck(){
      sub "Machine Health Checks"
      quote "Machine health checks automatically repair unhealthy machines in a particular machine pool."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/deploying-machine-health-checks.html#machine-health-checks-about_deploying-machine-health-checks"
      code 
      oc get machinehealthcheck -A 2>/dev/null >> ${adoc} 
      code 
   }

   # Includes 
   if ${machine_includes[list_machines]};then list_machines; fi 
   if ${machine_includes[list_machinesets]};then list_machinesets; fi 
   if ${machine_includes[machine_configs]};then machine_configs; fi 
   if ${machine_includes[degraded_machine_configs_pools]};then machine_configs_pools; fi 
   if ${machine_includes[machineautoscaler]};then machineautoscaler; fi 
   if ${machine_includes[clusterautoscaler]};then clusterautoscaler; fi 
   if ${machine_includes[machinehealthcheck]};then machinehealthcheck; fi 

}

etcd(){
   title "etcd"
   ns="openshift-etcd"
   # Getting 1 pod as target for internal verifications 
   t_pod=($(oc get pods -n ${ns} -l app=etcd -o Name | head -1))
   connect="oc exec -n ${ns} ${t_pod} -- "

   list_etcd_pods(){
      sub "etcd pods info"
      quote "For large and dense clusters, etcd can suffer from poor performance if the keyspace grows too large and exceeds the space quota."
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/recommended-host-practices.html#recommended-etcd-practices_recommended-host-practices"
      code 
      oc get pods -n ${ns} -l app=etcd >> ${adoc}
      code 
   }

   member_list(){
      sub "Members in the cluster"
      quote "For large and dense clusters, etcd can suffer from poor performance if the keyspace grows too large and exceeds the space quota."
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/recommended-host-practices.html#recommended-etcd-practices_recommended-host-practices"
      echo "[%header, %autowidth"] >> ${adoc}
      echo "|===" >> ${adoc}
      ${connect} etcdctl member list -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' >> ${adoc}
      echo "|===" >> ${adoc}
   }

   endpoint_status(){
      sub "Endpoints status"
      quote "Health check should be enabled on MachineConfig and routers endpoints."
      link "https://docs.openshift.com/container-platform/${cv}/networking/verifying-connectivity-endpoint.html"
      echo "[%header, %autowidth"] >> ${adoc}
      echo "|===" >> ${adoc}
      ${connect} etcdctl endpoint status --cluster -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' >> ${adoc}
      echo "|===" >> ${adoc} 
   }

   endpoint_health(){
      sub "Endpoints Health"
      quote "Health check should be enabled on MachineConfig and routers endpoints."
      link "https://docs.openshift.com/container-platform/${cv}/networking/verifying-connectivity-endpoint.html"
      echo "[%header, %autowidth"] >> ${adoc}
      echo "|===" >> ${adoc}
      ${connect} etcdctl endpoint health --cluster -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' >> ${adoc}
      echo "|===" >> ${adoc} 
   }

   # Includes 
   if ${etcd_includes[list_etcd_pods]};then list_etcd_pods; fi 
   if ${etcd_includes[member_list]};then member_list; fi 
   if ${etcd_includes[endpoint_status]};then endpoint_status; fi 
   if ${etcd_includes[endpoint_health]};then endpoint_health; fi 

}

pods(){
   title "pods"

   list_failing_pods(){
      sub "Failing pods"
      quote "A pod, is one or more containers deployed together on one host. Pods are the rough equivalent of a machine instance to a container."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      code 
      oc get pods -A | grep -vE 'Running|Completed' | column -t >> ${adoc}
      code 
   }

   constantly_restarted_pods(){
      sub "Constanstly restarted pods"
      quote "A pod, is one or more containers deployed together on one host. Pods are the rough equivalent of a machine instance to a container."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      code 
      oc get pods -A | grep -w Running | sort -nrk 5 | head -10 | column -t >> ${adoc}
      code 
   }

   long_running_pods(){
      sub "Long running pods"
      quote "A pod, is one or more containers deployed together on one host. Pods are the rough equivalent of a machine instance to a container."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      code 
      oc get pods -A | grep -w Running | grep -vE "[0-9]h$" | sort -hrk 6| head -10 | column -t >> ${adoc}
      code 
   }

   poddisruptionbudget(){
      sub "Pod Disruption Budget"
      quote "PodDisruptionBudget is an API object that specifies the minimum number or percentage of replicas that must be up at a time."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-configuring.html#nodes-pods-configuring-pod-distruption-about_nodes-pods-configuring"
      code 
      oc get poddisruptionbudget -A | column -t >> ${adoc}
      code 
   }

   pods_in_default(){
      sub "Pods in default namespace"
      quote "Pods in the default namespace are often installed by mistake or misconfigurations."
      code 
      oc get pods -n default -o wide 2>/dev/null | column -t >> ${adoc}
      code 
   }

   pods_per_node(){
      sub "Pods per node"
      code 
      oc get pods -A -o wide --no-headers | awk '{print $(NF-2)}' | sort | uniq -c | sort -n >> ${adoc}
      code 
   }

   # Includes 
   if ${pods_includes[list_failing_pods]};then list_failing_pods; fi 
   if ${pods_includes[constantly_restarted_pods]};then constantly_restarted_pods; fi 
   if ${pods_includes[long_running_pods]};then long_running_pods; fi 
   if ${pods_includes[poddisruptionbudget]};then poddisruptionbudget; fi 
   if ${pods_includes[pods_in_default]};then pods_in_default; fi 
   if ${pods_includes[pods_per_node]};then pods_per_node; fi 

}

security(){
   title "security"

   pending_csr(){
      sub "Pending CSRs"
      quote "When you add machines to a cluster, certificate signing requests (CSRs) are generated that you must confirm and approve."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/user_infra/adding-aws-compute-user-infra.html#installation-approve-csrs_adding-aws-compute-user-infra"
      code 
      oc get csr 2>/dev/null | grep -i pending >> ${adoc}
      code 
   }

   identities(){
      sub "Cluster Identities"
      quote "By default, only a kubeadmin user exists on your cluster. Identity providers create a Custom Resource that describes that identity provider and add it to the cluster."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/identity_providers/configuring-htpasswd-identity-provider.html#identity-provider-overview_configuring-htpasswd-identity-provider"
      code 
      oc get identity >> ${adoc}
      code 
      #TODO review if the result from `oc get users` is the same  
   }

   grants(){
      sub "Identities grants"
      quote "The OpenShift Container Platform control plane includes a built-in OAuth server. Developers and administrators obtain OAuth access tokens to authenticate themselves to the API."
      link "https://docs.openshift.com/container-platform/${cv}/post_installation_configuration/preparing-for-users.html"
      echo "==== Identities who can create users" >> ${adoc}
      code
      oc adm policy who-can create user | sed -n '/Users:/,/Groups:/p' | sed '$ d' >> ${adoc}
      code
      echo "==== Identities who can delete users" >> ${adoc}
      code
      oc adm policy who-can delete user | sed -n '/Users:/,/Groups:/p' | sed '$ d' >> ${adoc}
      code
   }

   rolebindings(){
      sub "Rolebindings"
      quote "Binding, or adding, a role to users or groups gives the user or group the access that is granted by the role."
      link "https://docs.openshift.com/container-platform/${cv}/post_installation_configuration/preparing-for-users.html#adding-roles_post-install-preparing-for-users"
      code 
      oc get rolebindings -A | head | column -t | awk '{print $1,$2,"\n","\t\t",$3}' >> ${adoc}
      code
   }

   clusterrolebinding(){
      sub "Cluster Rolebindings"
      quote "Binding, or adding, a role to users or groups gives the user or group the access that is granted by the role."
      link "https://docs.openshift.com/container-platform/${cv}/post_installation_configuration/preparing-for-users.html#adding-roles_post-install-preparing-for-users"
      code 
      oc get clusterrolebindings | awk '{print $1,$2}' | sed 's/ClusterRole\///g' | sort -k2 | column -t >> ${adoc}
      code
   }

   kubeadmin_secret(){
      sub "Kubeadmin Secret"
      quote "The user kubeadmin gets cluster-admin role automatically applied and is treated as the root user for the cluster. After installation and once an identity provider is configured is recommended to remove it."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/remove-kubeadmin.html"
      # oc -n kube-system get secret kubeadmin -o yaml | grep "kubeadmin:" | awk '{print $NF}' | base64 -d
      code 
      oc get secret -n kube-system kubeadmin 2>/dev/null >> ${adoc}
      code 
   }

   identity_providers(){
      sub "Identity Providers"
      quote "By default, only a kubeadmin user exists on your cluster. Identity providers create a Custom Resource that describes that identity provider and add it to the cluster."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/identity_providers/configuring-htpasswd-identity-provider.html#identity-provider-overview_configuring-htpasswd-identity-provider"
      code 
      oc get oauth cluster -o json | jq -r '.spec.identityProviders' >> ${adoc}
      code 
   }

   authentications(){
      sub "Cluster Authentications"
      quote "To interact with OCP, you must first authenticate to the cluster with a user associated in authorization layer by requests to the API."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/understanding-authentication.html"
      code 
      oc get authentications -o json 2>/dev/null | jq '.items[] | .metadata.annotations, .spec.webhookTokenAuthenticator, .status' >> ${adoc}
      code 
   }

   kubeletconfig(){
      sub "Kubelet Configurations"
      quote "OCP uses a KubeletConfig custom resource (CR) to manage the configuration of nodes that creates a managed machine config to override setting on the node."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/nodes/nodes-nodes-managing.html"
      code 
      oc get kubeletconfig -o json 2>/dev/null >> ${adoc}
      code       
   }

   subscriptions(){
      sub "Cluster Subscriptions"
      quote "Channels define a single event-forwarding and persistence layer. Events can be sent to multiple Knative services by using a subscription."
      link "https://docs.openshift.com/container-platform/${cv}/serverless/discover/serverless-channels.html"
      code 
      # oc get subscriptions -A 2>/dev/null >> ${adoc}
      #TODO: Extract status.catalogHealth.healty and name and at the end the conditions.type and the state 
      code 
   }

   webhooks(){
      sub "WebHook Configurations"
      quote "Webhooks allow Operator authors to intercept, modify, and accept or reject resources before they are saved to the object store and handled by the Operator controller."
      link "https://docs.openshift.com/container-platform/${cv}/operators/understanding/olm/olm-webhooks.html"
      code
      oc get validatingwebhookconfigurations -A -o json 2>/dev/null | jq '.items[].webhooks[]' | grep -v 'caBundle' >> ${adoc}
      # oc get validatingwebhookconfigurations -A 2>/dev/null >> ${adoc}
      code 
      sub "Mutating WebHook Configurations"
      code 
      oc get mutatingwebhookconfigurations -A -o json 2>/dev/null | jq '.items[].webhooks[]' | grep -v 'caBundle' >> ${adoc}
      # oc get mutatingwebhookconfigurations -A 2>/dev/null >> ${adoc}
      code 
   }

   api_versions(){
      sub "API Versions"
      apipods=$(oc get pods -n openshift-kube-apiserver -l app=openshift-kube-apiserver -o custom-columns=POD:.metadata.name --no-headers)
      controllerpods=$(oc get pods -n openshift-kube-controller-manager -l app=kube-controller-manager -o custom-columns=POD:.metadata.name --no-headers)
      schedulerpods=$(oc get pods -n openshift-kube-scheduler -l app=openshift-kube-scheduler -o custom-columns=POD:.metadata.name --no-headers)
      etcdpods=$(oc get pods -n openshift-etcd -l app=etcd -o custom-columns=POD:.metadata.name --no-headers)
      
      verify(){
         file=$1
         namespace=$2
         list=$3
         for pod in ${list[@]}
         do 
            result=($(oc exec -n ${namespace} ${pod} 2>/dev/null -- stat -c "%a %U %G" ${file}))
            if [[ "644" != ${result[0]} ]] || [[ "root" != ${result[1]} ]] || [[ "root" != ${result[2]} ]]
            then 
               echo "${file}: [ERROR] - ${result[@]}" >> ${adoc}
            else 
               echo "${file}: [OK]" >> ${adoc}
            fi 
         done 
      }

      echo "==== Verification of API files permissions" >> ${adoc}
      code
         verify "/etc/kubernetes/static-pod-resources/kube-apiserver-pod.yaml" "openshift-kube-apiserver" ${apipods[@]}
         verify "/etc/kubernetes/static-pod-resources/kube-controller-manager-pod.yaml" "openshift-kube-controller-manager" ${controllerpods[@]}
         verify "/etc/kubernetes/static-pod-resources/kube-scheduler-pod.yaml" "openshift-kube-scheduler" ${schedulerpods[@]}
         verify "/etc/kubernetes/manifests/etcd-pod.yaml" "openshift-etcd" ${etcdpods[@]}
      code

   }

   # Expiration of certificates in configmaps and secrets 
   # oc get configmaps -A  
   # oc get configmaps -n openshift-config   

   # Includes 
   if ${security_includes[pending_csr]};then pending_csr; fi 
   if ${security_includes[identities]};then identities; fi 
   if ${security_includes[grants]};then grants; fi 
   if ${security_includes[rolebindings]};then rolebindings; fi 
   if ${security_includes[clusterrolebinding]};then clusterrolebinding; fi 
   if ${security_includes[kubeadmin_secret]};then kubeadmin_secret; fi 
   if ${security_includes[identity_providers]};then identity_providers; fi 
   if ${security_includes[authentications]};then authentications; fi 
   if ${security_includes[kubeletconfig]};then kubeletconfig; fi 
   if ${security_includes[subscriptions]};then subscriptions; fi 
   if ${security_includes[webhooks]};then webhooks; fi 
   if ${security_includes[api_versions]};then api_versions; fi 

}

storage(){
   title "storage"

   pv_status(){
      quote "OCP uses persistent storage known as Persisten Volumes that allow you to access storage devices."
      link "https://docs.openshift.com/container-platform/${cv}/storage/understanding-persistent-storage.html#persistent-storage-overview_understanding-persistent-storage"
      statuses=(Failed Pending Released)
      for status in ${statuses[@]}
      do
         sub "${status} Persistent Volumes"
         code 
         oc get pv -A -o wide 2>/dev/null | grep -w ${status} | column -t >> ${adoc}
         code 
      done
   }

   pvc_status(){
      quote "OCP uses persistent storage claims to control request of persistent volumes."
      link "https://docs.openshift.com/container-platform/${cv}/storage/understanding-persistent-storage.html#persistent-volume-claims_understanding-persistent-storage"
      statuses=(Lost Pending)
      for status in ${statuses[@]}
      do
         sub "${status} Persistent Volumes Claims"
         code 
         oc get pvc -A -o wide 2>/dev/null | grep -w ${status} | column -t >> ${adoc}
         code 
      done
   }

   storage_classes(){
      sub "Storage Classes"
      quote "Claims can optionally request a specific storage class. Only PVs of the requested class, ones with the same storageClassName as the PVC, can be bound to the PVC."
      link "https://docs.openshift.com/container-platform/${cv}/storage/understanding-persistent-storage.html#pvc-storage-class_understanding-persistent-storage"
      code 
      oc get storageclasses 2>/dev/null >> ${adoc}
      code 
   }

   quotas(){
      sub "Quotas"
      quote "A resource quota provides constraints that limit aggregate resource consumption per project. It can limit the total amount of compute resources and storage that might be consumed by resources in that project."
      link "https://docs.openshift.com/container-platform/${cv}/applications/quotas/quotas-setting-per-project.html"
      code 
      oc get quota -A 2>/dev/null >> ${adoc}
      code 
   }

   volumeSnapshot(){
      sub "Volume Snapshots"
      quote "A snapshot represents the state of the storage volume in a cluster at a particular point in time. Volume snapshots can be used to provision a new volume."
      link "https://docs.openshift.com/container-platform/${cv}/storage/container_storage_interface/persistent-storage-csi-snapshots.html"
      code 
      oc get volumesnapshot -A 2>/dev/null | column -t >> ${adoc}
      code 
   }

   csidrivers(){
      sub "CSI Drivers"
      quote "CSI Drivers provision inline ephemeral volumes that contain the contents of Secret or ConfigMap objects."
      link "https://docs.openshift.com/container-platform/${cv}/storage/container_storage_interface/ephemeral-storage-shared-resource-csi-driver-operator.html"
      code 
      oc get csidrivers 2>/dev/null | column -t >> ${adoc}
      code 
   }

   csinodes(){
      sub "CSI Nodes"
      code 
      oc get csinodes 2>/dev/null | column -t >> ${adoc}
      code 
   }

   featuregate(){
      sub "Feature Gates"
      quote "FeatureGates enable specific feature sets in your cluster. A feature set is a collection of OpenShift Container Platform features that are not enabled by default."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/clusters/nodes-cluster-enabling-features.html"
      code 
      if [ "{}" != $(oc get featuregates -A -o json 2>/dev/null | jq -c '.items[].spec') ]
      then
         oc get featuregates -A -o json 2>/dev/null | jq -c '.items[].spec' >> ${adoc}
      fi 
      code 
   }

   horizontalpodautoscalers(){
      sub "Horizontal Pod AutoScalers"
      quote "You can create a horizontal pod autoscaler to specify the minimum and maximum number of pods you want to run, as well as the CPU utilization or memory utilization your pods should target."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-autoscaling.html"
      code 
      oc get horizontalpodautoscalers -A 2>/dev/null >> ${adoc}
      code 
   }

   # Includes 
   if ${storage_includes[pv_status]};then pv_status; fi 
   if ${storage_includes[pvc_status]};then pvc_status; fi 
   if ${storage_includes[storage_classes]};then storage_classes; fi 
   if ${storage_includes[quotas]};then quotas; fi 
   if ${storage_includes[volumeSnapshot]};then volumeSnapshot; fi
   if ${storage_includes[csidrivers]};then csidrivers; fi
   if ${storage_includes[csinodes]};then csinodes; fi
   if ${storage_includes[featuregate]};then featuregate; fi
   if ${storage_includes[horizontalpodautoscalers]};then horizontalpodautoscalers; fi

   #TODO: Based on the available storage classes create a PVC and PV and delete for each 
      # Create and Delete PVC 
      # Create and Delete PV
      # Create and Delete Annotated Local Storage
      # Create and Delete Local Storage Operator Group
      # Create and Delete Local Storage operator subscription
      # Statically provisioning hostPath volumes
   #TODO: add  images, prune and imagestreams

} 

performance(){
   title "performance"

   nodes_memory(){
      limit=21
      sub "Nodes memory utilization"
      quote "All nodes meet the minimum requirements and are currently allocated to an amount appropriate to handle the workloads deployed to the cluster"
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/planning-your-environment-according-to-object-maximums.html#cluster-maximums-environment_object-limits"
      code 
      oc adm top nodes --no-headers | sort -nrk5 2>/dev/null | head -${limit} >> ${adoc}
      code 
   }

   nodes_cpu(){
      limit=21
      sub "Nodes CPU utilization"
      quote "All nodes meet the minimum requirements and are currently allocated to an amount appropriate to handle the workloads deployed to the cluster"
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/planning-your-environment-according-to-object-maximums.html#cluster-maximums-environment_object-limits"
      code 
      oc adm top nodes --no-headers | sort -nrk3 2>/dev/null | head -${limit} >> ${adoc}
      code 
   }

   pods_memory(){
      sub "Pods memory utilization"
      quote "As an administrator, you can view the pods in your cluster and to determine the health of those pods and the cluster as a whole."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      code 
      oc adm top pods -A --sort-by=memory 2>/dev/null | head -21 | column -t >> ${adoc}
      code 
   }

   pods_cpu(){
      sub "Pods CPU utilization"
      quote "As an administrator, you can view the pods in your cluster and to determine the health of those pods and the cluster as a whole."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      code 
      oc adm top pods -A --sort-by=cpu 2>/dev/null | head -21 | column -t >> ${adoc}
      code 
   }

   # Includes 
   if ${performance_includes[nodes_memory]};then nodes_memory; fi 
   if ${performance_includes[nodes_cpu]};then nodes_cpu; fi 
   if ${performance_includes[pods_memory]};then pods_memory; fi 
   if ${performance_includes[pods_cpu]};then pods_cpu; fi 

   # oc get tuned -A 
   # oc get limits -A 
   # oc get appliedclusterresourcequotas -A 
}

logging(){
   title "logging"

   logging_resources(){
      sub "Logging Resources"
      quote "The logging subsystem aggregates all the logs from the cluster and stores them in a default log store. You can use the Kibana web console to visualize log data."
      link "https://docs.openshift.com/container-platform/4.10/logging/cluster-logging.html"
      code 
      oc get all -n openshift-logging 2>/dev/null >> ${adoc}
      code 
   }

   # Includes 
   if ${logging_includes[logging_resources]};then logging_resources; fi 
   # oc get all -n openshift-logging | grep collector | awk '{print $3}' | sort | uniq -cd 
   # oc get all -n openshift-logging daemonset.apps/collector | grep -A10 Selector 

}

monitoring (){
   title "Monitoring"

   prometheus(){
      cont=true
      sub "Prometheus Status"
      quote "The monitoring stack provides monitoring for core platform components. You also have the option to enable monitoring for user-defined projects."
      link "https://docs.openshift.com/container-platform/4.10/monitoring/monitoring-overview.html"
      code 
      oc get pods -n openshift-monitoring | grep prometheus 2>/dev/null >> ${adoc}
      if [ $? == 0 ]
      then
         cont=true
      else  
         cont=false
      fi 
      code
      if [ cont ]
      then  
         sub "Prometheus Context"
         code 
         oc get prometheuses -A -o json 2>/dev/null | jq -c '.items[].spec | .securityContext,.retention,.resources' >> ${adoc}
         code 
      fi
   }

   prometheus_rules(){
      sub "Prometheus Rules"
      quote "Users can then create and configure user-defined alert routing by creating or editing the AlertmanagerConfig objects."
      link "https://docs.openshift.com/container-platform/${cv}/monitoring/enabling-alert-routing-for-user-defined-projects.html"
      cont=true
      oc get pods -n openshift-monitoring | grep prometheus &> /dev/null 
      if [ $? == 0 ]
      then
         while read LINE 
         do 
            echo "==== ${LINE}" >> ${adoc}
            code 
            oc get prometheusrules -n openshift-sdn networking-rules -o json | jq -c '.spec[][].rules[] | .alert,.labels' | tr -d "\n" | sed 's/}/}\n/g' | tr -d "\"" >> ${adoc}
            code 
         done < <(oc get prometheusrules -A --no-headers 2>/dev/null | awk '{print $1,$2}')
      fi 
   }

   servicemonitors(){
      sub "Service Monitors"
      quote "Cluster components are monitored by scraping metrics exposed through service endpoints. You can also configure metrics collection for user-defined projects."
      link "https://docs.openshift.com/container-platform/${cv}/monitoring/managing-metrics.html"
      code 
      oc get servicemonitors -A 2>/dev/null | awk '{print $1,$2}' | column -t >> ${adoc}
      code 
   }

   podmonitors(){
      sub "Pod Monitors"
      code 
      oc get podmonitors -A 2>/dev/null | awk '{print $1,$2}' | column -t >> ${adoc}
      code 
   }

   alertmanagers(){
      sub "Alert Managers"
      code 
      oc get alertmanagers -A 2>/dev/null >> ${adoc}
      code 
   }

   agents(){
      sub "Monitoring Agents & Dashboards"
      expect=(
         cluster-monitoring-operator
         kube-state-metrics
         openshift-state-metrics
         node-exporter
         thanos-querier
         grafana
         telemeter-client
      )
      oc get pods -n openshift-monitoring 2>/dev/null | grep -w Running > /tmp/ocp-health.tmp 
      echo "[%header,cols='3,1']" >> ${adoc}
      echo "|===" >> ${adoc}
      echo "|Agent|Status" >> ${adoc}
      for val in ${expect[@]}
      do 
         grep ${val} /tmp/ocp-health.tmp >/dev/null 
         if [ $? -eq 0 ]
         then 
            echo "|${val}|OK" >> ${adoc}
         else
            echo "|${val}|ERROR" >> ${adoc} 
         fi 
      done 
      rm /tmp/ocp-health.tmp 
      echo "|===" >> ${adoc}
   }

   # Includes 
   if ${monitoring_includes[prometheus]};then prometheus; fi 
   if ${monitoring_includes[prometheus_rules]};then prometheus_rules; fi 
   if ${monitoring_includes[servicemonitors]};then servicemonitors; fi 
   if ${monitoring_includes[podmonitors]};then podmonitors; fi 
   if ${monitoring_includes[alertmanagers]};then alertmanagers; fi 
   if ${monitoring_includes[agents]};then agents; fi 

}

network(){
   title "network"

   enabled_network(){
      sub "Enabled Networks"
      quote "By default, OCP allocates each pod an internal IP address and Pods and their containers can network, but clients outside the cluster do not have networking access."
      link "https://docs.openshift.com/container-platform/${cv}/networking/understanding-networking.html"
      code 
      oc get network cluster -o json 2>/dev/null | jq '.spec' >> ${adoc}
      code 
   }

   networkpolicies(){
      sub "Network Policies"
      quote "In a cluster using a Kubernetes Container Network Interface (CNI) plug-in that supports Kubernetes network policy, network isolation is controlled entirely by NetworkPolicy objects."
      link "https://docs.openshift.com/container-platform/${cv}/networking/network_policy/about-network-policy.html"
      for policy in $(oc get networkpolicies -A --no-headers 2>/dev/null | awk '{print $1,$2}')
      do 
         if [ -z ${policy} ]
         then 
            echo "==== ${policy}" >> ${adoc}
            code 
            oc get networkpolicies -n ${policy} -o json 2>/dev/null | jq -r '.spec' >> ${adoc}
            code 
         fi 
      done
   }

   clusternetworks(){
      sub "Cluster Networks"
      quote "ClusterNetwork describes the cluster network. There is normally only one object of this type, named 'default', which is created by the SDN network plugin based on the master configuration when the cluster is brought up for the first time."
      link "https://docs.openshift.com/container-platform/${cv}/rest_api/network_apis/clusternetwork-network-openshift-io-v1.html"
      code 
      oc get clusternetworks 2>/dev/null >> ${adoc}
      code 
   }

   hostsubnet(){
      sub "Host Subnets"
      quote "HostSubnet describes the container subnet network on a node. The HostSubnet object must have the same name as the Node object it corresponds to."
      link "https://docs.openshift.com/container-platform/${cv}/rest_api/network_apis/hostsubnet-network-openshift-io-v1.html"
      code 
      oc get hostsubnet 2>/dev/null >> ${adoc}
      code 
   }

   proxy(){
      sub "Cluster Proxy"
      quote "If a global proxy is configured on the OpenShift Container Platform cluster, OLM automatically configures Operators that it manages with the cluster-wide proxy."
      link "https://docs.openshift.com/container-platform/${cv}/operators/admin/olm-configuring-proxy-support.html"
      code 
      oc get proxy cluster -o json 2>/dev/null | jq '.' >> ${adoc}
      code 
   }

   endpoints(){
      sub "Network Endpoints"
      code
      oc get endpoints -A 2>/dev/null | head | column -t | awk '{$5=$3} {$3="\n"} {$4="\t\t"} {print $0}' >> ${adoc}
      code
   }

   podnetworkconnectivitycheck(){
      sub "Pod Network Connectivity Check"
      quote "The Cluster Network Operator runs a controller that performs a connection health check between resources within your cluster. By reviewing the results of the health checks, you can diagnose connection problems or eliminate network connectivity as the cause of an issue that you are investigating."
      link "https://docs.openshift.com/container-platform/4.10/networking/verifying-connectivity-endpoint.html#nw-pod-network-connectivity-checks_verifying-connectivity-endpoint"
      ns="openshift-network-diagnostics"
      echo "[%header,cols='4,1']" >> ${adoc}
      echo "|===" >> ${adoc}
      echo "|POD|STATUS" >> ${adoc}
      for pod in $(oc get podnetworkconnectivitycheck -n ${ns}  2>/dev/null | awk '{print $1}')
      do 
         echo "|${pod}|$(oc get podnetworkconnectivitycheck ${pod} -n ${ns} -o json 2>/dev/null | jq '.status.conditions[].type' | tr -d '"' )" >> ${adoc}
      done
      echo "|===" >> ${adoc}
   }

   route(){
      sub "Routes"
      quote "A route allows you to host your application at a public URL. It can either be secure or unsecured, depending on the network security configuration of your application."
      link "https://docs.openshift.com/container-platform/${cv}/networking/routes/route-configuration.html"
      code 
      oc get route -A 2>/dev/null | awk '{print $1,$2,"\n","\t\t",$3,$4,$5,$6,$7,$8}' >> ${adoc}
      code 
   }

   egressnetworkpolicy(){
      sub "Egress Network Policy"
      quote "You can create an egress firewall for a project that restricts egress traffic leaving your OpenShift Container Platform cluster."
      link "https://docs.openshift.com/container-platform/${cv}/networking/openshift_sdn/configuring-egress-firewall.html"
      code 
      oc get egressnetworkpolicy -A 2>/dev/null >> ${adoc}
      code 
   }

   ingresscontrollers(){
      sub "Ingress Controllers"
      quote "OpenShift Container Platform provides methods for communicating from outside the cluster with services running in the cluster. This method uses an Ingress Controller."
      link "https://docs.openshift.com/container-platform/${cv}/networking/nw-ingress-controller-endpoint-publishing-strategies.html"
      for ingctl in $(oc get ingresscontrollers -n openshift-ingress-operator --no-headers | awk '{print $1}')
      do 
         echo "==== ${ingctl}" >> ${adoc}
         echo "" >> ${adoc}
         while read LINE 
         do 
            echo "- ${LINE}" >> ${adoc}
         done < <(oc get ingresscontrollers -n openshift-ingress-operator -o json | jq '.items[].status.conditions[] | .message' | grep -v null)
         echo "" >> ${adoc}
      done 
   }

   ingresses(){
      sub "Ingresses"
      quote "OpenShift Container Platform provides methods for communicating from outside the cluster with services running in the cluster. This method uses an Ingress Controller."
      link "https://docs.openshift.com/container-platform/${cv}/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-ingress-controller.html"
      code 
      oc get ingresses -A 2>/dev/null >> ${adoc} 
      code 
   }

   ingress_controler_pods(){
      sub "Ingress Controler Pods"
      quote "OpenShift Container Platform provides methods for communicating from outside the cluster with services running in the cluster. This method uses an Ingress Controller."
      link "https://docs.openshift.com/container-platform/${cv}/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-ingress-controller.html"
      for pod in $(oc get pods -n openshift-ingress --no-headers | awk '{print $1}')
      do
         echo "**${pod}**" >> ${adoc}
         echo "**haproxy.conf $(oc exec -n openshift-ingress ${pod} -- haproxy -c -f haproxy.config)**" >> ${adoc}
         code 
         echo "SSL Configurations:" >> ${adoc}
         oc exec -n openshift-ingress ${pod} -- grep ssl-default-bind haproxy.config >> ${adoc}
         echo "Frontends:" >> ${adoc}
         oc exec -n openshift-ingress ${pod} -- sed -n '/^defaults/,/\Z/p' haproxy.config | grep -wE "frontend |bind |default_backend "  >> ${adoc}
         echo "Backends:" >> ${adoc}
         oc exec -n openshift-ingress ${pod} -- grep -e ^backend haproxy.config >> ${adoc}
         code 
      done

   }

   mtu_size(){
      clustermtu=$(oc get clusternetworks -o json| jq '.items[].mtu ')
      clustersubnet=$(oc get clusternetworks -o json| jq '.items[].network' | tr -d '"' | cut -c1-7)
      nodemtu=$(oc debug $(oc get nodes --no-headers -o name | head -1) -- ip a 2>/dev/null | grep ${clustersubnet} -B2 | grep mtu | awk -Fmtu '{print $2}' | awk '{print $1}';)
      if [ ${clustermtu} -lt ${nodemtu} ]
      then
         sub "MTU Size"
         quote "The MTU setting of the OpenShift SDN is greater than one on the physical network. Severe fragmentation and performance degradation will occur."
         link "https://docs.openshift.com/container-platform/${cv}/networking/changing-cluster-network-mtu.html"
      fi
   }

   # Includes 
   if ${network_includes[enabled_network]};then enabled_network; fi 
   if ${network_includes[networkpolicies]};then networkpolicies; fi 
   if ${network_includes[clusternetworks]};then clusternetworks; fi 
   if ${network_includes[hostsubnet]};then hostsubnet; fi 
   if ${network_includes[proxy]};then proxy; fi 
   if ${network_includes[endpoints]};then endpoints; fi 
   if ${network_includes[route]};then route; fi 
   if ${network_includes[egressnetworkpolicy]};then egressnetworkpolicy; fi 
   if ${network_includes[ingresscontrollers]};then ingresscontrollers; fi 
   if ${network_includes[ingresses]};then ingresses; fi 
   if ${network_includes[ingress_controler_pods]};then ingress_controler_pods; fi 
   if ${network_includes[mtu_size]};then mtu_size; fi 
   if ${network_includes[podnetworkconnectivitycheck]};then podnetworkconnectivitycheck; fi 

 #TODO: 
 # for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- ip a; echo "=====";done  node_ips.out
 # for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host /usr/bin/chronyc -m sources tracking; echo "=====";done  node_times.out


}

operators(){
   title "operators"

   operators_degraded(){
      sub "Degraded Cluster Operators"
      quote "Operators are a method of packaging, deploying, and managing an OpenShift Container Platform application. They act like an extension of the software vendor’s engineering team, watching over an OpenShift Container Platform environment and using its current state to make decisions in real time."
      link "https://docs.openshift.com/container-platform/${cv}/support/troubleshooting/troubleshooting-operator-issues.html"
      code
      oc get clusteroperators --no-headers | awk '$5 == "True"' >> ${adoc}
      code
   }

   operators_unavailable(){
      sub "Unavailable Cluster Operators"
      quote "Operators are a method of packaging, deploying, and managing an OpenShift Container Platform application. They act like an extension of the software vendor’s engineering team, watching over an OpenShift Container Platform environment and using its current state to make decisions in real time."
      link "https://docs.openshift.com/container-platform/${cv}/support/troubleshooting/troubleshooting-operator-issues.html"
      code
      oc get clusteroperators --no-headers |awk '$3 == "False"' >> ${adoc}
      code
   }

   cluster_services(){
      sub "Cluster Services Versions"
      quote "A cluster service version (CSV), is a YAML manifest created from Operator metadata that assists Operator Lifecycle Manager (OLM) in running the Operator in a cluster."
      link "https://docs.openshift.com/container-platform/${cv}/operators/operator_sdk/osdk-generating-csvs.html"
      code 
      oc get clusterserviceversion -A -o wide >> ${adoc}
      code 
   }

   operatorgroups(){
      sub "Operator Groups"
      quote "An Operator group, defined by the OperatorGroup resource, provides multitenant configuration to OLM-installed Operators. An Operator group selects target namespaces in which to generate required RBAC access for its member Operators."
      link "https://docs.openshift.com/container-platform/${cv}/operators/understanding/olm/olm-understanding-operatorgroups.html"
      code 
      oc get operatorgroups -A 2>/dev/null >> ${adoc}
      code 
   }

   operatorsources(){
      sub "Operator Sources"
      code 
      oc get operatorsources -A 2>/dev/null  >> ${adoc}
      code 
   }

   # Includes 
   if ${operators_includes[operators_degraded]};then operators_degraded; fi 
   if ${operators_includes[operators_unavailable]};then operators_unavailable; fi 
   if ${operators_includes[cluster_services]};then cluster_services; fi 
   if ${operators_includes[operatorgroups]};then operatorgroups; fi 
   if ${operators_includes[operatorsources]};then operatorsources; fi 
}

mesh(){
   cont='false' 

   serviceMeshControlPlane(){
      oc get servicemeshcontrolplane -A &>/dev/null
      if [ $? == 0 ]
      then 
         title "Service Mesh"
         cont='true'
         sub "Service Mesh ControlPlane"
         code 
         oc get servicemeshcontrolplane -A 2>/dev/null  >> ${adoc}
         code 
      fi
   }

   serviceMeshMember(){
      if [ cont == 'true' ]
      then
         sub "Service Mesh Members"
         code
         oc get servicemeshmember -A 2>/dev/null  >> ${adoc}
         code 
      fi
   }

   serviceMeshMemberRoll(){
      if [ cont == 'true' ]
      then 
         sub "Service Mesh Member Rolls"
         code 
         oc get servicemeshmemberroll -A 2>/dev/null  >> ${adoc}
         code 
      fi
   }

   # Includes 
   if ${operators_includes[serviceMeshControlPlane]};then serviceMeshControlPlane; fi 
   if ${operators_includes[serviceMeshMember]};then serviceMeshMember; fi 
   if ${operators_includes[serviceMeshMemberRoll]};then serviceMeshMemberRoll; fi 

}

applications(){
   title "Applications"

   deploy_demo_app(){
      sub "Openshif Deployments"
      code
      # Create Schrodinger's cat project
      oc new-project schrodingers-cat | head -1 >> ${adoc}
      # Deploy application if project succeded
      oc project schrodingers-cat >/dev/null
      if [ $? -eq 0 ]
      then 
         # Create Sample App
         oc new-app https://github.com/sclorg/nodejs-ex -l name=sample_app | grep '\-\-\>' >> ${adoc}
         sleep 10
         # Verify application status
         oc status | grep "svc/nodejs-ex" >> ${adoc}
         if [ $? -ne 0 ]
         then 
            echo "WARNING: Unable to deploy DEMO application!" >> ${adoc}
         else
            echo "Application Deployment: SUCCESS!" >> ${adoc}
         fi
         # Delete Schrodinger's cat project
         oc delete project schrodingers-cat >> ${adoc}
      else
         echo "WARNING: Unable to create DEMO project!" >> ${adoc}
      fi
      code
   }

   non_ready_deployments(){
      sub "Non-Ready Deployments"
      code
      oc get deployment -A | grep -E "0/[0-9]|NAMESPACE" | column -t >> ${adoc}
      code
   }

   non_available_deployments(){
      sub "Unavailable Deployments"
      code 
      oc get deployment -A | awk '$(NF-1)=="0" || $1=="NAMESPACE"' | column -t >> ${adoc}
      code 
   }

   inactive_projects(){
      sub "Inactive projects"
      code 
      oc get projects | awk '$NF =! "Active"' >> ${adoc}
      code 
   }

   failed_builds(){
      sub "Failed Builds"
      code 
      oc get builds -A | awk '$5 =! "Complete"' >> ${adoc}
      code 
   }

   # Includes 
   #if ${application_includes[deploy_demo_app]};then deploy_demo_app; fi 
   if ${application_includes[non_ready_deployments]};then non_ready_deployments; fi 
   if ${application_includes[non_available_deployments]};then non_available_deployments; fi 
   if ${application_includes[failed_builds]};then failed_builds; fi 
   if ${application_includes[inactive_projects]};then inactive_projects; fi 

   #TODO: Verify that installed applications are not using deprectated api versions
   # oc get apiservices.apiregistration.k8s.io 

}

# Main 

environment_setup
commons
nodes 
machines
etcd 
pods 
performance
security
storage 
logging 
monitoring  
network 
operators
mesh
applications   #TODO uncomment the deployment 
generate_pdf

# EndOfScript
