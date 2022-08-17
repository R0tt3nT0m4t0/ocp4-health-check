#!/usr/bin/env bash
# Openshift 4 Health Check Report Generator 
# Author: jumedina@redhat.com 
# -------------------------
# Install and setup asciidocs
# -------------------------
# sudo dnf install -y asciidoctor ruby
# gem install asciidoctor-pdf  
# gem install asciidoctor-diagram  

# Global Variables 

customer=''; adoc=''; namespaces=''; cv='';

# Functions 

environment_setup(){
   if [ -z ${1} ]
   then 
      echo "A short customer name is required"
      exit 
   fi 
   global customer=${1}

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

   global namespaces=$(oc get namespaces --no-headers | awk '{print $1}')
   global cv=$(oc version | grep Server | awk '{print $3}' | sed -e 's/.[0-9][0-9]$//g')  # cluster version  
   # Making sure the schrodingers-cat project doesn't exist 
   oc delete project schrodingers-cat &>/dev/null 

   # Setting up report.adoc
   
   global adoc="pdf/report.adoc"
   rm ${adoc}
   rm pdf/table.adoc
   echo ":author: Red Hat Consulting" >> ${adoc}
   echo ":toc:" >> ${adoc}
   echo ":numbered:" >> ${adoc}
   echo ":doctype: book" >> ${adoc}
   echo ":imagesdir: ../images/" >> ${adoc}
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
      asciidoctor-pdf --verbose -r asciidoctor-diagram -o "../${report}" report.adoc 
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

codeblock(){ 
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

executive_summary(){
   if [ ${include_executive_summary} ] && [ -f pdf/executive.adoc ]
   then 
      cat pdf/executive.adoc >> ${adoc}
      echo "" >> ${adoc}
      echo "@TABLE_PLACEHOLDER@" >> ${adoc}
      echo "" >> ${adoc}
   else 
      echo "The pdf/executive.adoc file was not found. Will continue without executive summary"
   fi 
}

table(){
   # Executive Summary Include in Table 
   # Receives 2 parameters 
   # Area
   # Result [PASS, FAIL, REVIEW]
   tadoc="pdf/table.adoc"
   valid="PASS FAIL REVIEW"
   if [ ! -f ${tadoc} ]
   then 
      touch  ${tadoc}
      echo "[%header,cols='5,1']" >> ${tadoc}
      echo "|===" >> ${tadoc}
      echo "|Area|Result" >> ${tadoc}
   else 
      if [[ "close_table_now" == ${1} ]]
      then 
         echo "|===" >> ${tadoc}
         sed -ie '/@TABLE_PLACEHOLDER@/ r pdf/table.adoc' ${adoc}
         sed -i '/@TABLE_PLACEHOLDER@/d' ${adoc}
      else
         if grep -q ${2} <<< ${valid}
         then 
            echo "|${1}|${2}" >> ${tadoc}
         else 
            echo "Executive Summary table value ${2} for ${1} is not valid. Ignored!."
         fi 
      fi
   fi 
}

commons(){
   title "Commons"

   versions(){
      sub "Versions"
      quote "Red Hat OpenShift Container Platform Life Cycle Policy"
      link "https://access.redhat.com/support/policy/updates/openshift"
      codeblock 
      oc version >> ${adoc}
      codeblock 
      table "Versions" "PASS"
   }

   componentstatuses(){
      sub "Components status"
      quote "ComponentStatus (and ComponentStatusList) holds the cluster validation info. Deprecated: This API is deprecated in v1.19+"
      link "https://docs.openshift.com/container-platform/${cv}/rest_api/metadata_apis/componentstatus-v1.html"
      codeblock
      oc get componentstatuses 2>/dev/null >> ${adoc}
      codeblock
      table "Components status" "PASS"
   }

   cluster_status_failing_conditions(){
      sub "Cluster Status Conditions"
      quote "ClusterOperatorStatusCondition represents the state of the operator’s managed and monitored components."
      link "https://docs.openshift.com/container-platform/${cv}/installing/validating-an-installation.html#getting-cluster-version-and-update-details_validating-an-installation"
      codeblock 
      if [ "True" == $(oc get clusterversion -o=jsonpath='{range .items[0].status.conditions[?(@.type=="Failing")]}{.status}') ]
      then
         oc get clusterversion -o=json | jq '.items[].status.conditions' >> ${adoc}
         table "Cluster Status Conditions" "REVIEW"
      else
         echo "All conditions are Normal" >> ${adoc}
         table "Cluster Status Conditions" "PASS"
      fi
      codeblock 
   }

   cluster_events_abnormal(){
      sub "Cluster Abnormal Events"
      quote "Events are records of important life-cycle information and are useful for monitoring and troubleshooting resource scheduling, creation, and deletion issues."
      link "https://docs.openshift.com/container-platform/${ns}/virt/logging_events_monitoring/virt-events.html#virt-about-vm-events_virt-events"
      codeblock 
      oc get events --field-selector type!=Normal -A --no-headers | awk '{print $1,$3,$4,$5}' | sort | uniq >> ${adoc} 
      if (( $(oc get events --field-selector type!=Normal -A --no-headers | awk '{print $1,$3,$4,$5}' | sort | uniq | wc -l) > 0 ))
      then 
         table "Cluster Abnormal Events" "REVIEW"
      else 
         table "Cluster Abnoral Events" "PASS"
      fi
      codeblock 
   }

   cluster_api_status(){
      sub "Cluster API Server Status"
      api_url=$(oc whoami --show-server)
      codeblock 
         curl -k ${api_url} 2>/dev/null | grep 403 >/dev/null 
         if [ $? != 0 ]
         then 
            echo "API Server Status: FAILED" >> ${adoc}
            table "API Server Status" "FAIL"
         else 
            echo "API Server Status: SUCCEEDED" >> ${adoc}
            table "API Server Status" "PASS"
         fi 
      codeblock 
   }

   cluster_console_status(){
      sub "Cluster Console Status"
      console_url=$(oc whoami --show-console)
      codeblock 
         curl -k ${console_url} 2>/dev/null | grep "<title>Red Hat OpenShift Container Platform</title>" >/dev/null 
         if [ $? != 0 ]
         then 
            echo "Console Status: FAILED" >> ${adoc}
            table "Console Status" "FAIL"
         else 
            echo "Console Status: SUCCEEDED" >> ${adoc}
            table "Console Status" "PASS"
         fi 
      codeblock 
   }

   # Includes 
   versions
   componentstatuses
   cluster_status_failing_conditions
   cluster_events_abnormal
   cluster_api_status
   cluster_console_status
}

nodes(){
   title "nodes"

   cluster_nodes_status(){
      sub "Cluster Nodes Status"
      codeblock 
      oc get nodes --no-headers | awk '$2 != "Ready"' >> ${adoc}
      if [ -z $(oc get nodes --no-headers | awk '$2 != "Ready"') ]
      then
         echo "All node conditions are Ready!"  >> ${adoc}
         table "Cluster Nodes Status" "PASS"
      else 
         table "Cluster Nodes Status" "FAIL"
      fi 
      codeblock 
   }

   cluster_nodes_conditions(){
      sub "Cluster Node Conditions"
      labels=(master worker infra)
      for type in ${labels[@]}
      do
         echo "==== ${type} Nodes" >> ${adoc}
         state="PASS" 
         for node in $(oc get nodes --no-headers | sed 's/,/ /g' | awk '{print $1, $3}' | grep ${type} | awk '{print $1}')
         do
            results=$(oc get node ${node} -o json | \
               jq -cr '.status.conditions[] | {type,status,reason}' | \
               tr -d '{}"' | \
               sed 's/type://g; s/status://g; s/reason://g; s/,/ /g' | \
               grep 'Pressure' | grep True)
            if [ -z ${results+x} ]
            then 
               echo "**${node}**" >> ${adoc}
               codeblock
               echo ${results} >> ${adoc}
               codeblock
               state="REVIEW"
            fi
         done
         echo "" >> ${adoc}
         table "Cluster Nodes Conditions ${type}" ${state}
      done

   }

   nodes_capacity(){
      sub "Nodes Capacity"
      echo "[%header,cols='3,1,1,1,2,2']" >> ${adoc}
      echo "|===" >> ${adoc}
      echo "|NODE|TYPE|OS|CPU|MEM|STORAGE" >> ${adoc}
      labels=(master worker infra)
      state="PASS"
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
            echo "|${node}|${type}|${os}|${capacity[0]}|${capacity[1]}|${capacity[2]}" >> ${adoc}
            state="REVIEW"
         done
      done 
      table "Cluster Nodes Capacity" ${state}
      echo "|===" >> ${adoc}
   }

   customresourcedefinitions(){
      sub "Custom Resource Definitions"
      quote "A custom resource definition (CRD) object defines a new, unique object type, called a kind, in the cluster and lets the Kubernetes API server handle its entire lifecycle."
      link "https://docs.openshift.com/container-platform/${cv}/operators/understanding/crds/crd-extending-api-with-crds.html" 
      for crd in $(oc get customresourcedefinitions --no-headers | awk '{print $1}')
      do
         result=$(oc get customresourcedefinitions \
            volumereplicationclasses.replication.storage.openshift.io -o json | \
            jq '.status.conditions[].status')
         if grep -q False <<< ${result}
         then 
            echo "**${crd}**" >> ${adoc}
            codeblock
            oc get customresourcedefinitions \
            volumereplicationclasses.replication.storage.openshift.io -o json | \
            jq '.status.conditions' >> ${adoc}
            codeblock
            table "Custom Resource Definitions" "REVIEW"
         fi
      done 
   }

   clusterresourcequotas(){
      sub "Cluster Resource Quotas"
      quote "A multi-project quota, defined by a ClusterResourceQuota object, allows quotas to be shared across multiple projects."
      link "https://docs.openshift.com/container-platform/${cv}/applications/quotas/quotas-setting-across-multiple-projects.html"
      codeblock 
      oc get clusterresourcequotas.quota.openshift.io -A --no-headers 2>/dev/null >> ${adoc}
      if (( $(oc get clusterresourcequotas.quota.openshift.io -A --no-headers 2>/dev/null | wc -l) > 0 ))
      then 
         table "Cluster Resource Quotas" "REVIEW"
      else 
         table "Cluster Resource Quotas" "PASS"
      fi
      codeblock 
   }

   clusterserviceversions(){
      sub "Cluster Service Versions"
      quote "A multi-project quota, defined by a ClusterResourceQuota object, allows quotas to be shared across multiple projects."
      link "https://docs.openshift.com/container-platform/${cv}/applications/quotas/quotas-setting-across-multiple-projects.html"
      codeblock
      oc get clusterserviceversions.operators.coreos.com -A 2>/dev/null | grep -v Succeeded >> ${adoc}
      if (( $(oc get clusterserviceversions.operators.coreos.com -A --no-headers 2>/dev/null | grep -v Succeeded | wc -l) > 0 ))
      then 
         table "Cluster Service Versions" "FAIL"
      else 
         table "Cluster Service Versions" "PASS"
      fi
      codeblock 
   }

   # Includes 
   cluster_nodes_status
   cluster_nodes_conditions
   nodes_capacity
   customresourcedefinitions
   clusterresourcequotas
   clusterserviceversions

} 

machines(){
   title "Machines"

   list_machines(){
      sub "Machine Information"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      codeblock 
      oc get machines -A 2>/dev/null | grep -v Running >> ${adoc}
      if (( $(oc get machines -A --no-headers 2>/dev/null | grep -v Running | wc -l) > 0 ))
      then 
         table "Machine Information" "FAIL"
      else 
         table "Machine Information" "PASS"
      fi
      codeblock
   }

   list_machinesets(){
      sub "Machinesets Information"
            quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      codeblock 
      state="PASS"
      while read LINE 
      do 
         machineset=(${LINE})
         if (( ${machineset[2]} > 0 )) && [[ ${machineset[2]} != ${machineset[5]} ]]
         then 
            echo  ${machineset[@]} >> ${adoc}
            state="FAIL"
         fi
      done < <(oc get machinesets -A 2>/dev/null )
      table "Machinesets Information" ${state}
      codeblock 
   }

   machine_configs(){
      sub "Machine Configs"
         quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      codeblock 
      oc get nodes machineconfig 2>/dev/null >> ${adoc}
      table "Machine Configs" "PASS"
      codeblock 
   }

   machine_configs_pools(){
      sub "Machine Config Pools"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      codeblock 
      oc get nodes machineconfigpools 2>/dev/null >> ${adoc}
      table "Machine Config Pools" "PASS"
      codeblock 
   }

   machineautoscaler(){
      sub "Machine Auto Scalers"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html"
      codeblock 
      oc get machineautoscaler -A 2>/dev/null >> ${adoc}  
      table "Machine Auto Scalers" "REVIEW"
      codeblock 
   }

   clusterautoscaler(){
      sub "Cluster Auto Scalers"
      quote "Using machine management you can perform auto-scaling based on specific workload policies."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/index.html" 
      for CA in $(oc get clusterautoscaler --no-headers 2>/dev/null | awk '{print $1}')
      do 
         echo "==== ${CA}" >> ${adoc}
         codeblock
         oc get clusterautoscaler ${CA} -o json 2>/dev/null | jq '.' >> ${adoc} 
         codeblock
         echo "" >> ${adoc}
      done 
      table "Cluster Auto Scalers" "REVIEW"
   }

   machinehealthcheck(){
      sub "Machine Health Checks"
      quote "Machine health checks automatically repair unhealthy machines in a particular machine pool."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/deploying-machine-health-checks.html#machine-health-checks-about_deploying-machine-health-checks"
      state="PASS"
      codeblock 
      echo "NAMESPACE NAME MAXUNHEALTHY EXPECTEDMACHINES CURRENTHEALTHY"  >> ${adoc}
      while read LINE 
      do 
         machinehealthcheck=(${LINE})
         if (( ${machinehealthcheck[3]} > 0 )) && [[ ${machinehealthcheck[3]} != ${machinehealthcheck[4]} ]]
         then 
            echo  ${machinehealthcheck[@]} >> ${adoc}
            state="FAIL"
         fi
      done < <(oc get machinehealthcheck -A --no-headers 2>/dev/null)
      codeblock 
      table "Machine Health Checks" ${state}
   }

   # Includes 
   list_machines
   list_machinesets
   machine_configs
   machine_configs_pools
   machineautoscaler
   clusterautoscaler
   machinehealthcheck

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
      codeblock 
      oc get pods -n ${ns} -l app=etcd >> ${adoc}
      codeblock 
      table "etcd pods info" "REVIEW"
   }

   member_list(){
      sub "Failing members in the cluster"
      quote "For large and dense clusters, etcd can suffer from poor performance if the keyspace grows too large and exceeds the space quota."
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/recommended-host-practices.html#recommended-etcd-practices_recommended-host-practices"
      echo "[%header, %autowidth"] >> ${adoc}
      echo "|===" >> ${adoc}
      ${connect} etcdctl member list -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' | grep -vE "STATUS|started" >> ${adoc}
      echo "|===" >> ${adoc}
      if (( $( ${connect} etcdctl member list -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' | grep -vE "STATUS|started" | wc -l ) > 0 ))
      then
         table "Failing members in the cluster" "FAIL"
      else
         table "Failing members in the cluster" "PASS"
      fi
   }

   endpoint_status(){
      sub "Endpoints status"
      quote "Health check should be enabled on MachineConfig and routers endpoints."
      link "https://docs.openshift.com/container-platform/${cv}/networking/verifying-connectivity-endpoint.html"
      echo "[%header, %autowidth"] >> ${adoc}
      echo "|===" >> ${adoc}
      ${connect} etcdctl endpoint status --cluster -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' >> ${adoc}
      echo "|===" >> ${adoc} 
      table "Endpoints status" "REVIEW"
   }

   endpoint_health(){
      sub "Endpoints Health"
      quote "Health check should be enabled on MachineConfig and routers endpoints."
      link "https://docs.openshift.com/container-platform/${cv}/networking/verifying-connectivity-endpoint.html"
      echo "[%header, %autowidth"] >> ${adoc}
      echo "|===" >> ${adoc}
      ${connect} etcdctl endpoint health --cluster -w table 2>/dev/null | grep -v "+-" | sed 's/..$//' >> ${adoc}
      echo "|===" >> ${adoc} 
      table "Endpoints Health" "REVIEW"
   }

   # Includes 
   list_etcd_pods
   member_list
   endpoint_status
   endpoint_health

}

pods(){
   title "pods"

   list_failing_pods(){
      sub "Failing pods"
      quote "A pod, is one or more containers deployed together on one host. Pods are the rough equivalent of a machine instance to a container."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      codeblock 
      oc get pods -A | grep -vE 'Running|Completed' | column -t >> ${adoc}
      if (( $(oc get pods -A --no-headers | grep -vE 'Running|Completed' | wc -l ) > 0 ))
      then
         table "Failing pods" "FAIL"
      else
         table "Failing pods" "PASS"
      fi
      codeblock 
   }

   constantly_restarted_pods(){
      sub "Constanstly restarted pods"
      quote "A pod, is one or more containers deployed together on one host. Pods are the rough equivalent of a machine instance to a container."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      codeblock 
      oc get pods -A | grep -w Running | sort -nrk 5 | head -10 | column -t >> ${adoc}
      codeblock 
      table "Constanstly restarted pods" "REVIEW"
   }

   long_running_pods(){
      sub "Long running pods"
      quote "A pod, is one or more containers deployed together on one host. Pods are the rough equivalent of a machine instance to a container."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      codeblock 
      oc get pods -A | grep -w Running | grep -vE "[0-9]h$" | sort -hrk 6| head -10 | column -t >> ${adoc}
      codeblock 
      table "Long running pods" "REVIEW"
   }

   poddisruptionbudget(){
      sub "Pod Disruption Budget"
      quote "PodDisruptionBudget is an API object that specifies the minimum number or percentage of replicas that must be up at a time."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-configuring.html#nodes-pods-configuring-pod-distruption-about_nodes-pods-configuring"
      codeblock 
      oc get poddisruptionbudget -A | column -t >> ${adoc}
      codeblock 
      table "Pod Disruption Budget" "REVIEW"
   }

   pods_in_default(){
      sub "Pods in default namespace"
      quote "Pods in the default namespace are often installed by mistake or misconfigurations."
      codeblock 
      oc get pods -n default -o wide 2>/dev/null | column -t >> ${adoc}
      codeblock 
      table "Pods in default namespace" "REVIEW"
   }

   pods_per_node(){
      sub "Pods per node"
      codeblock 
      oc get pods -A -o wide --no-headers | awk '{print $(NF-2)}' | sort | uniq -c | sort -n >> ${adoc}
      codeblock 
      table "Pods per node" "REVIEW"
   }

   # Includes 
   list_failing_pods
   constantly_restarted_pods
   long_running_pods
   poddisruptionbudget
   pods_in_default
   pods_per_node

}

security(){
   title "security"

   pending_csr(){
      sub "Pending CSRs"
      quote "When you add machines to a cluster, certificate signing requests (CSRs) are generated that you must confirm and approve."
      link "https://docs.openshift.com/container-platform/${cv}/machine_management/user_infra/adding-aws-compute-user-infra.html#installation-approve-csrs_adding-aws-compute-user-infra"
      codeblock 
      oc get csr 2>/dev/null | grep -i pending >> ${adoc}
      codeblock 
      if (( $(oc get csr 2>/dev/null | grep -i pending | wc -l ) > 0 ))
      then
         table "Pending CSRs" "FAIL"
      else
         table "Pending CSRs" "PASS"
      fi
   }

   identities(){
      sub "Cluster Identities"
      quote "By default, only a kubeadmin user exists on your cluster. Identity providers create a Custom Resource that describes that identity provider and add it to the cluster."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/identity_providers/configuring-htpasswd-identity-provider.html#identity-provider-overview_configuring-htpasswd-identity-provider"
      codeblock 
      oc get identity >> ${adoc}
      codeblock 
      table "Cluster Identities" "REVIEW"
      #TODO review if the result from `oc get users` is the same  
   }

   grants(){
      sub "Identities grants"
      quote "The OpenShift Container Platform control plane includes a built-in OAuth server. Developers and administrators obtain OAuth access tokens to authenticate themselves to the API."
      link "https://docs.openshift.com/container-platform/${cv}/post_installation_configuration/preparing-for-users.html"
      echo "==== Identities who can create users" >> ${adoc}
      codeblock
      oc adm policy who-can create user | sed -n '/Users:/,/Groups:/p' | sed '$ d' >> ${adoc}
      codeblock
      echo "==== Identities who can delete users" >> ${adoc}
      codeblock
      oc adm policy who-can delete user | sed -n '/Users:/,/Groups:/p' | sed '$ d' >> ${adoc}
      codeblock
      table "Identities grants" "REVIEW"
   }

   rolebindings(){
      sub "Rolebindings"
      quote "Binding, or adding, a role to users or groups gives the user or group the access that is granted by the role."
      link "https://docs.openshift.com/container-platform/${cv}/post_installation_configuration/preparing-for-users.html#adding-roles_post-install-preparing-for-users"
      codeblock 
      oc get rolebindings -A | head | column -t | awk '{print $1,$2,"\n","\t\t",$3}' >> ${adoc}
      codeblock
      table "Rolebindings" "REVIEW"
   }

   clusterrolebinding(){
      sub "Cluster Rolebindings"
      quote "Binding, or adding, a role to users or groups gives the user or group the access that is granted by the role."
      link "https://docs.openshift.com/container-platform/${cv}/post_installation_configuration/preparing-for-users.html#adding-roles_post-install-preparing-for-users"
      codeblock 
      oc get clusterrolebindings | awk '{print $1,$2}' | sed 's/ClusterRole\///g' | sort -k2 >> ${adoc}
      codeblock
      table "Cluster Rolebindings" "REVIEW"
   }

   kubeadmin_secret(){
      sub "Kubeadmin Secret"
      quote "The user kubeadmin gets cluster-admin role automatically applied and is treated as the root user for the cluster. After installation and once an identity provider is configured is recommended to remove it."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/remove-kubeadmin.html"
      # oc -n kube-system get secret kubeadmin -o yaml | grep "kubeadmin:" | awk '{print $NF}' | base64 -d
      codeblock 
      oc get secret -n kube-system kubeadmin 2>/dev/null >> ${adoc}
      codeblock 
      if (( $(oc get secret -n kube-system kubeadmin --no-headers 2>/dev/null | wc -l ) > 0 ))
      then
         table "Kubeadmin Secret" "FAIL"
      else
         table "Kubeadmin Secret" "PASS"
      fi
   }

   identity_providers(){
      sub "Identity Providers"
      quote "By default, only a kubeadmin user exists on your cluster. Identity providers create a Custom Resource that describes that identity provider and add it to the cluster."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/identity_providers/configuring-htpasswd-identity-provider.html#identity-provider-overview_configuring-htpasswd-identity-provider"
      codeblock 
      oc get oauth cluster -o json | jq -r '.spec.identityProviders' >> ${adoc}
      codeblock 
      table "Identity Providers" "REVIEW"
   }

   authentications(){
      sub "Cluster Authentications"
      quote "To interact with OCP, you must first authenticate to the cluster with a user associated in authorization layer by requests to the API."
      link "https://docs.openshift.com/container-platform/${cv}/authentication/understanding-authentication.html"
      codeblock 
      oc get authentications -o json 2>/dev/null | jq '.items[] | .metadata.annotations, .spec.webhookTokenAuthenticator, .status' >> ${adoc}
      codeblock 
      table "Cluster Authentications" "REVIEW"
   }

   kubeletconfig(){
      sub "Kubelet Configurations"
      quote "OCP uses a KubeletConfig custom resource (CR) to manage the configuration of nodes that creates a managed machine config to override setting on the node."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/nodes/nodes-nodes-managing.html"
      codeblock 
      oc get kubeletconfig -o json 2>/dev/null >> ${adoc}
      codeblock
      table "Kubelet Configurations" "REVIEW"
   }

   subscriptions(){
      sub "Cluster Subscriptions"
      quote "Channels define a single event-forwarding and persistence layer. Events can be sent to multiple Knative services by using a subscription."
      link "https://docs.openshift.com/container-platform/${cv}/serverless/discover/serverless-channels.html"

      echo "==== Subscriptions from non-stable channels" >> ${adoc}
      codeblock 
      oc get subscriptions -A 2>/dev/null >> ${adoc}
      codeblock
      if (( $(oc get subscriptions -A --no-headers 2>/dev/null | grep -v stable | wc -l ) > 0 ))
      then
         table "Cluster Subscriptions from non-stable channels" "FAIL"
      else
         table "Cluster Subscriptions from non-stable channels" "PASS"
      fi

      echo "==== Subscriptions Catalog Health" >> ${adoc}
      state="PASS"
      for pod in $(oc get subscriptions -A --no-headers 2>/dev/null | awk '{print $1,$2}')
      do 
         if (( $(oc get subscriptions -n ${pod} -o json | jq '. | .status.catalogHealth[].healthy' 2>/dev/null | grep -v true | wc -l ) > 0 ))
         then 
            echo "**${pod}**"
            codeblock
            oc get subscriptions -n ${pod} -o json | jq '. | .status.catalogHealth[]' 2>/dev/null >> ${adoc}
            state="FAIL"
            codeblock
         fi 
      done 
      table "Cluster Subscriptions Catalog Health" ${state}      
      
      echo "==== Subscriptions Conditions" >> ${adoc}
      state="PASS"
      for pod in $(oc get subscriptions -A --no-headers 2>/dev/null | awk '{print $1,$2}')
      do 
         if (( $(oc get subscriptions -n ${pod} -o json | jq '. | .status.conditions[].status' 2>/dev/null | grep -v False | wc -l) > 0 ))
         then 
            echo "**${pod}**"
            codeblock
            oc get subscriptions -n openshift-operators openshift-gitops-operator -o json | jq '. | .status.conditions[]' 2>/dev/null >> ${adoc}
            state="FAIL"
            codeblock
         fi 
      done 
      table "Cluster Subscriptions Conditions" ${state}   
   }

   webhooks(){
      sub "WebHook Configurations"
      quote "Webhooks allow Operator authors to intercept, modify, and accept or reject resources before they are saved to the object store and handled by the Operator controller."
      link "https://docs.openshift.com/container-platform/${cv}/operators/understanding/olm/olm-webhooks.html"
      codeblock
      oc get validatingwebhookconfigurations -A -o json 2>/dev/null | jq '.items[].webhooks[]' | grep -v 'caBundle' >> ${adoc}
      # oc get validatingwebhookconfigurations -A 2>/dev/null >> ${adoc}
      codeblock 
      sub "Mutating WebHook Configurations"
      codeblock 
      oc get mutatingwebhookconfigurations -A -o json 2>/dev/null | jq '.items[].webhooks[]' | grep -v 'caBundle' >> ${adoc}
      # oc get mutatingwebhookconfigurations -A 2>/dev/null >> ${adoc}
      codeblock 
      table "WebHooks" "REVIEW"
   }

   api_versions(){
      sub "API Versions"
      state="PASS"
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
               state="FAIL"
            else 
               echo "${file}: [OK]" >> ${adoc}
            fi 
         done 
      }

      echo "==== Verification of API files permissions" >> ${adoc}
      codeblock
         verify "/etc/kubernetes/static-pod-resources/kube-apiserver-pod.yaml" "openshift-kube-apiserver" ${apipods[@]}
         verify "/etc/kubernetes/static-pod-resources/kube-controller-manager-pod.yaml" "openshift-kube-controller-manager" ${controllerpods[@]}
         verify "/etc/kubernetes/static-pod-resources/kube-scheduler-pod.yaml" "openshift-kube-scheduler" ${schedulerpods[@]}
         verify "/etc/kubernetes/manifests/etcd-pod.yaml" "openshift-etcd" ${etcdpods[@]}
      codeblock
      table "API Versions" ${state}
   }

   # Expiration of certificates in configmaps and secrets 
   # oc get configmaps -A  
   # oc get configmaps -n openshift-config   

   # Includes 
   pending_csr
   identities
   grants
   rolebindings
   clusterrolebinding
   kubeadmin_secret
   identity_providers
   authentications
   kubeletconfig
   subscriptions
   webhooks
   api_versions

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
         codeblock 
         oc get pv -A -o wide 2>/dev/null | grep -w ${status} | column -t >> ${adoc}
         if (( $(oc get pv -A -o wide 2>/dev/null | grep -w ${status} | wc -l ) > 0 ))
         then
            table "PV Status ${status}" "FAIL"
         else
            table "PV Status ${status}" "PASS"
         fi
         codeblock 
      done
   }

   pvc_status(){
      quote "OCP uses persistent storage claims to control request of persistent volumes."
      link "https://docs.openshift.com/container-platform/${cv}/storage/understanding-persistent-storage.html#persistent-volume-claims_understanding-persistent-storage"
      statuses=(Lost Pending)
      for status in ${statuses[@]}
      do
         sub "${status} Persistent Volumes Claims"
         codeblock 
         oc get pvc -A -o wide 2>/dev/null | grep -w ${status} | column -t >> ${adoc}
         if (( $(oc get pvc -A -o wide 2>/dev/null | grep -w ${status} | wc -l ) > 0 ))
         then
            table "PVC Status ${status}" "FAIL"
         else
            table "PVC Status ${status}" "PASS"
         fi
         codeblock 
      done
   }

   storage_classes(){
      sub "Storage Classes"
      quote "Claims can optionally request a specific storage class. Only PVs of the requested class, ones with the same storageClassName as the PVC, can be bound to the PVC."
      link "https://docs.openshift.com/container-platform/${cv}/storage/understanding-persistent-storage.html#pvc-storage-class_understanding-persistent-storage"
      codeblock 
      oc get storageclasses 2>/dev/null >> ${adoc}
      codeblock 
      table "Storage Classes" "REVIEW"
   }

   quotas(){
      sub "Quotas"
      quote "A resource quota provides constraints that limit aggregate resource consumption per project. It can limit the total amount of compute resources and storage that might be consumed by resources in that project."
      link "https://docs.openshift.com/container-platform/${cv}/applications/quotas/quotas-setting-per-project.html"
      codeblock 
      oc get quota -A 2>/dev/null >> ${adoc}
      codeblock 
      table "Quotas" "REVIEW"
   }

   volumeSnapshot(){
      sub "Volume Snapshots Age"
      threshold=90
      state="PASS"
      quote "A snapshot represents the state of the storage volume in a cluster at a particular point in time. Volume snapshots can be used to provision a new volume."
      link "https://docs.openshift.com/container-platform/${cv}/storage/container_storage_interface/persistent-storage-csi-snapshots.html"
      codeblock 
      while read LINE 
      do 
         data=(${LINE})
         if [[ ${data[0]} == "NAMESPACE" ]]
         then 
            echo ${data[@]} | column -t >> ${adoc} 
         else
            if (( $(echo ${data[-1]} | tr -d "d") > ${threshold} ))
            then
               echo ${data[@]} | column -t >> ${adoc}
               state="FAIL"
            fi
         fi
      done < <(oc get volumesnapshot -A 2>/dev/null)
      codeblock 
      table "Volume Snapshots Age" ${state}
   }

   csidrivers(){
      sub "CSI Drivers"
      quote "CSI Drivers provision inline ephemeral volumes that contain the contents of Secret or ConfigMap objects."
      link "https://docs.openshift.com/container-platform/${cv}/storage/container_storage_interface/ephemeral-storage-shared-resource-csi-driver-operator.html"
      codeblock 
      oc get csidrivers 2>/dev/null | column -t >> ${adoc}
      codeblock 
      table "CSI Drivers" "REVIEW"
   }

   csinodes(){
      sub "CSI Nodes"
      codeblock 
      oc get csinodes 2>/dev/null | column -t >> ${adoc}
      codeblock 
      table  "CSI Nodes" "REVIEW"
   }

   featuregate(){
      sub "Feature Gates"
      quote "FeatureGates enable specific feature sets in your cluster. A feature set is a collection of OpenShift Container Platform features that are not enabled by default."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/clusters/nodes-cluster-enabling-features.html"
      codeblock 
      if [ "{}" != $(oc get featuregates -A -o json 2>/dev/null | jq -c '.items[].spec') ]
      then
         oc get featuregates -A -o json 2>/dev/null | jq -c '.items[].spec' >> ${adoc}
      fi 
      codeblock 
      table "Feature Gates" "REVIEW"
   }

   horizontalpodautoscalers(){
      sub "Horizontal Pod AutoScalers"
      quote "You can create a horizontal pod autoscaler to specify the minimum and maximum number of pods you want to run, as well as the CPU utilization or memory utilization your pods should target."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-autoscaling.html"
      codeblock 
      oc get horizontalpodautoscalers -A 2>/dev/null >> ${adoc}
      codeblock 
      table "Horizontal Pod AutoScalers" "REVIEW"
   }

   # Includes 
   pv_status
   pvc_status
   storage_classes
   quotas
   volumeSnapshot
   csidrivers
   csinodes
   featuregate
   horizontalpodautoscalers

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
      sub "Nodes Memory Utilization"
      quote "All nodes meet the minimum requirements and are currently allocated to an amount appropriate to handle the workloads deployed to the cluster"
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/planning-your-environment-according-to-object-maximums.html#cluster-maximums-environment_object-limits"
      codeblock 
      oc adm top nodes --no-headers | sort -nrk5 2>/dev/null | head -${limit} | awk '{print $1,$4,$5}' >> ${adoc}
      codeblock 
      table "Nodes Memory Utilization" "REVIEW"
   }

   nodes_cpu(){
      limit=21
      sub "Nodes CPU Utilization"
      quote "All nodes meet the minimum requirements and are currently allocated to an amount appropriate to handle the workloads deployed to the cluster"
      link "https://docs.openshift.com/container-platform/${cv}/scalability_and_performance/planning-your-environment-according-to-object-maximums.html#cluster-maximums-environment_object-limits"
      codeblock 
      oc adm top nodes --no-headers | sort -nrk3 2>/dev/null | head -${limit} | awk '{print $1,$2,$3}' >> ${adoc}
      codeblock 
      table "Nodes CPU Utilization" "REVIEW"
   }

   pods_memory(){
      sub "Pods Memory Utilization"
      quote "As an administrator, you can view the pods in your cluster and to determine the health of those pods and the cluster as a whole."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      codeblock 
      oc adm top pods -A --sort-by=memory --no-headers 2>/dev/null | head -21 | column -t | awk '{print $1,$2,$4}' >> ${adoc}
      codeblock 
      table "Pods Memory Utilization" "REVIEW"
   }

   pods_cpu(){
      sub "Pods CPU utilization"
      quote "As an administrator, you can view the pods in your cluster and to determine the health of those pods and the cluster as a whole."
      link "https://docs.openshift.com/container-platform/${cv}/nodes/pods/nodes-pods-viewing.html"
      codeblock 
      oc adm top pods -A --sort-by=cpu --no-headers 2>/dev/null | head -21 | column -t | awk '{print $1,$2,$3}' >> ${adoc}
      codeblock 
      table "Pods CPU Utilization" "REVIEW"
   }

   # Includes 
   nodes_memory
   nodes_cpu
   pods_memory
   pods_cpu

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
      codeblock 
      oc get all -n openshift-logging 2>/dev/null >> ${adoc}
      codeblock 
   }

   # Includes 
   logging_resources
   # oc get all -n openshift-logging | grep collector | awk '{print $3}' | sort | uniq -cd 
   # oc get all -n openshift-logging daemonset.apps/collector | grep -A10 Selector 

}

monitoring (){
   title "Monitoring"

   prometheus(){
      sub "Prometheus Status"
      quote "The monitoring stack provides monitoring for core platform components. You also have the option to enable monitoring for user-defined projects."
      link "https://docs.openshift.com/container-platform/4.10/monitoring/monitoring-overview.html"
      oc get pods -n openshift-monitoring | grep prometheus 2>/dev/null >> ${adoc}
      if (( $(oc get pods -n openshift-monitoring | grep prometheus 2>/dev/null | wc -l ) > 0 ))
      then  
         sub "Prometheus Context"
         codeblock 
         oc get prometheuses -A -o json 2>/dev/null | jq -c '.items[].spec | .securityContext,.retention,.resources' >> ${adoc}
         codeblock 
      fi
      table "Prometheus Status" "REVIEW"
   }

   prometheus_rules(){
      sub "Prometheus Rules"
      quote "Users can then create and configure user-defined alert routing by creating or editing the AlertmanagerConfig objects."
      link "https://docs.openshift.com/container-platform/${cv}/monitoring/enabling-alert-routing-for-user-defined-projects.html"
      if (( $(oc get pods -n openshift-monitoring | grep prometheuss 2>/dev/null | wc -l ) > 0 ))
      then
         while read LINE 
         do 
            echo "==== ${LINE}" >> ${adoc}
            codeblock 
            oc get prometheusrules -n openshift-windows-machine-config-operator windows-prometheus-k8s-rules \
               -o json 2>/dev/null | jq '.spec[][] | .name,.rules[].expr' >> ${adoc}
            codeblock 
         done < <(oc get prometheusrules -A --no-headers 2>/dev/null | awk '{print $1,$2}')
      fi 
      table "Prometheus Rules" "REVIEW"
   }

   servicemonitors(){
      sub "Service Monitors"
      quote "Cluster components are monitored by scraping metrics exposed through service endpoints. You can also configure metrics collection for user-defined projects."
      link "https://docs.openshift.com/container-platform/${cv}/monitoring/managing-metrics.html"
      codeblock 
      oc get servicemonitors -A 2>/dev/null | awk '{print $1,$2}' | column -t >> ${adoc}
      codeblock 
      table "Sevice Monitors" "REVIEW" 
   }

   podmonitors(){
      sub "Pod Monitors"
      codeblock 
      oc get podmonitors -A 2>/dev/null | awk '{print $1,$2}' | column -t >> ${adoc}
      codeblock 
      table "Pod Monitors" "REVIEW" 
   }

   alertmanagers(){
      sub "Alert Managers"
      codeblock 
      oc get alertmanagers -A 2>/dev/null >> ${adoc}
      codeblock 
      table "Alert Managers" "REVIEW" 
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
      state="PASS"
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
            state="FAIL"
         fi 
      done 
      rm /tmp/ocp-health.tmp 
      echo "|===" >> ${adoc}
      table "Monitoring Agents & Dashboards" ${state}
   }

   # Includes 
   prometheus
   prometheus_rules
   servicemonitors
   podmonitors
   alertmanagers
   agents

}

network(){
   title "network"

   enabled_network(){
      sub "Enabled Networks"
      quote "By default, OCP allocates each pod an internal IP address and Pods and their containers can network, but clients outside the cluster do not have networking access."
      link "https://docs.openshift.com/container-platform/${cv}/networking/understanding-networking.html"
      codeblock 
      oc get network cluster -o json 2>/dev/null | jq '.spec' >> ${adoc}
      codeblock 
      table "Enabled Networks" "REVIEW"
   }

   networkpolicies(){
      sub "Network Policies"
      quote "In a cluster using a Kubernetes Container Network Interface (CNI) plug-in that supports Kubernetes network policy, network isolation is controlled entirely by NetworkPolicy objects."
      link "https://docs.openshift.com/container-platform/${cv}/networking/network_policy/about-network-policy.html"
      while read LINE 
      do 
         data=(${LINE})
         echo "==== ${data[@]}"  >> ${adoc}
         codeblock 
         oc get networkpolicies -n ${data[@]} -o json | jq -c '.spec | "ingress:",.ingress,"Egress:",.egress'  | tr -d '"[]{}' >> ${adoc}
         codeblock 
         echo "" >> ${adoc}
      done < <(oc get networkpolicies -A --no-headers 2>/dev/null | awk '{print $1,$2}')
      table "Network Policies" "REVIEW"
   }

   clusternetworks(){
      sub "Cluster Networks"
      quote "ClusterNetwork describes the cluster network. There is normally only one object of this type, named 'default', which is created by the SDN network plugin based on the master configuration when the cluster is brought up for the first time."
      link "https://docs.openshift.com/container-platform/${cv}/rest_api/network_apis/clusternetwork-network-openshift-io-v1.html"
      codeblock 
      oc get clusternetworks 2>/dev/null >> ${adoc}
      codeblock 
      table "Cluster Networks" "REVIEW"
   }

   hostsubnet(){
      sub "Host Subnets"
      quote "HostSubnet describes the container subnet network on a node. The HostSubnet object must have the same name as the Node object it corresponds to."
      link "https://docs.openshift.com/container-platform/${cv}/rest_api/network_apis/hostsubnet-network-openshift-io-v1.html"
      codeblock 
      oc get hostsubnet 2>/dev/null >> ${adoc}
      codeblock 
      table "Host Subnets" "REVIEW"
   }

   proxy(){
      sub "Cluster Proxy"
      quote "If a global proxy is configured on the OpenShift Container Platform cluster, OLM automatically configures Operators that it manages with the cluster-wide proxy."
      link "https://docs.openshift.com/container-platform/${cv}/operators/admin/olm-configuring-proxy-support.html"
      codeblock 
      oc get proxy cluster -o json 2>/dev/null | jq '.' >> ${adoc}
      codeblock 
      table "Cluster Proxy" "REVIEW"
   }

   endpoints(){
      sub "Network Endpoints"
      codeblock
      oc get endpoints -A 2>/dev/null | column -t | awk '{$5=$3} {$3="\n"} {$4="\t\t"} {print $0}' >> ${adoc}
      codeblock
      table "Network Endpoints" "REVIEW"
   }

   podnetworkconnectivitycheck(){
      sub "Pod Network Connectivity Check"
      quote "The Cluster Network Operator runs a controller that performs a connection health check between resources within your cluster. By reviewing the results of the health checks, you can diagnose connection problems or eliminate network connectivity as the cause of an issue that you are investigating."
      link "https://docs.openshift.com/container-platform/4.10/networking/verifying-connectivity-endpoint.html#nw-pod-network-connectivity-checks_verifying-connectivity-endpoint"
      ns="openshift-network-diagnostics"
      state="PASS"
      echo "[%header,cols='4,1']" >> ${adoc}
      echo "|===" >> ${adoc}
      echo "|POD|STATUS" >> ${adoc}
      for pod in $(oc get podnetworkconnectivitycheck -n ${ns} --no-headers  2>/dev/null | awk '{print $1}')
      do 
         status=$(oc get podnetworkconnectivitycheck ${pod} -n ${ns} --no-headers -o json 2>/dev/null | \
            jq '.status.conditions[].type' | tr -d '"' )
         if grep -qv "Reachable" <<< ${status}
         then
            echo "|${pod}|${status}" >> ${adoc}
            state="FAIL"
         fi
      done
      echo "|===" >> ${adoc}
      table "Pod Network Connectivity Check" ${state}
   }

   route(){
      sub "Routes"
      quote "A route allows you to host your application at a public URL. It can either be secure or unsecured, depending on the network security configuration of your application."
      link "https://docs.openshift.com/container-platform/${cv}/networking/routes/route-configuration.html"
      codeblock 
      oc get route -A 2>/dev/null | awk '{print $1,$2,"\n","\t\t",$3,$4,$5,$6,$7,$8}' >> ${adoc}
      codeblock 
      table "Routes" "REVIEW"
   }

   egressnetworkpolicy(){
      sub "Egress Network Policy"
      quote "You can create an egress firewall for a project that restricts egress traffic leaving your OpenShift Container Platform cluster."
      link "https://docs.openshift.com/container-platform/${cv}/networking/openshift_sdn/configuring-egress-firewall.html"
      codeblock 
      oc get egressnetworkpolicy -A 2>/dev/null >> ${adoc}
      codeblock 
      table "Egress Network Policy" "REVIEW"
   }

   ingresscontrollers(){
      sub "Ingress Controllers"
      quote "OpenShift Container Platform provides methods for communicating from outside the cluster with services running in the cluster. This method uses an Ingress Controller."
      link "https://docs.openshift.com/container-platform/${cv}/networking/nw-ingress-controller-endpoint-publishing-strategies.html"
      for ingctl in $(oc get ingresscontrollers -n openshift-ingress-operator --no-headers | awk '{print $1}')
      do 
         echo "==== ${ingctl}" >> ${adoc}
         codeblock 
         oc get ingresscontrollers -n openshift-ingress-operator ${ingctl} -o json 2>/dev/null | jq '.status' >> ${adoc}
         codeblock 
      done 
      table "Ingress Controllers" "REVIEW"
   }

   ingresses(){
      sub "Ingresses"
      quote "OpenShift Container Platform provides methods for communicating from outside the cluster with services running in the cluster. This method uses an Ingress Controller."
      link "https://docs.openshift.com/container-platform/${cv}/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-ingress-controller.html"
      codeblock 
      oc get ingresses -A 2>/dev/null >> ${adoc} 
      codeblock 
      table "Ingresses" "REVIEW"
   }

   ingress_controler_pods(){
      sub "Ingress Controller Pods"
      quote "OpenShift Container Platform provides methods for communicating from outside the cluster with services running in the cluster. This method uses an Ingress Controller."
      link "https://docs.openshift.com/container-platform/${cv}/networking/configuring_ingress_cluster_traffic/configuring-ingress-cluster-traffic-ingress-controller.html"
      for ingctl in $(oc get ingresscontrollers -n openshift-ingress-operator --no-headers | awk '{print $1}')
      do 
         for pod in $(oc get pods -n openshift-ingress --no-headers | grep ${ingctl} | head -1 | awk '{print $1}')
         do
            echo "**${pod}**" >> ${adoc}
            echo "**haproxy.conf $(oc exec -n openshift-ingress ${pod} -- haproxy -c -f haproxy.config)**" >> ${adoc}
            codeblock 
            echo "SSL Configurations:" >> ${adoc}
            oc exec -n openshift-ingress ${pod} -- grep ssl-default-bind haproxy.config >> ${adoc}
            echo "Frontends:" >> ${adoc}
            oc exec -n openshift-ingress ${pod} -- sed -n '/^defaults/,/\Z/p' haproxy.config | grep -wE "frontend |bind |default_backend "  >> ${adoc}
            echo "Backends:" >> ${adoc}
            oc exec -n openshift-ingress ${pod} -- grep -e ^backend haproxy.config >> ${adoc}
            codeblock 
         done
      done
      table "Ingress Controller Pods" "REVIEW"
   }

   mtu_size(){
      clustermtu=$(oc get clusternetworks -o json 2>/dev/null | jq '.items[].mtu ')
      clustersubnet=$(oc get clusternetworks -o json 2>/dev/null | jq '.items[].network' | tr -d '"' | cut -c1-7)
      if [ -z ${clustermtu+x} ] || [ -z ${clustersubnet+x} ]
      then 
         nodemtu=$(oc debug $(oc get nodes --no-headers -o name 2>/dev/null| head -1) -- ip a 2>/dev/null | grep ${clustersubnet} -B2 | grep mtu | awk -Fmtu '{print $2}' | awk '{print $1}';)
         if [ ${clustermtu} -lt ${nodemtu} ]
         then
            sub "MTU Size"
            quote "The MTU setting of the OpenShift SDN is greater than one on the physical network. Severe fragmentation and performance degradation will occur."
            link "https://docs.openshift.com/container-platform/${cv}/networking/changing-cluster-network-mtu.html"
            table "MTU Size" "REVIEW"
         fi
      fi
   }

   # Includes 
   enabled_network
   networkpolicies
   clusternetworks
   hostsubnet
   proxy
   endpoints
   route
   egressnetworkpolicy
   ingresscontrollers
   ingresses
   ingress_controler_pods
   mtu_size
   podnetworkconnectivitycheck

 #TODO: 
 # for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- ip a; echo "=====";done 
 # for NODE in `oc get node --no-headers|awk '{print$1}'`; do echo $NODE; oc debug node/$NODE -- chroot /host /usr/bin/chronyc -m sources tracking; echo "=====";done 
}

operators(){
   title "operators"

   operators_degraded(){
      sub "Degraded Cluster Operators"
      quote "Operators are a method of packaging, deploying, and managing an OpenShift Container Platform application. They act like an extension of the software vendor’s engineering team, watching over an OpenShift Container Platform environment and using its current state to make decisions in real time."
      link "https://docs.openshift.com/container-platform/${cv}/support/troubleshooting/troubleshooting-operator-issues.html"
      codeblock
      oc get clusteroperators --no-headers | awk '$5 == "True"' >> ${adoc}
      if (( $(oc get clusteroperators --no-headers | awk '$5 == "True"' | wc -l ) > 0 ))
      then 
         table "Degraded Cluster Operators" "FAIL"
      else
         table "Degraded Cluster Operators" "PASS"
      fi
      codeblock
   }

   operators_unavailable(){
      sub "Unavailable Cluster Operators"
      quote "Operators are a method of packaging, deploying, and managing an OpenShift Container Platform application. They act like an extension of the software vendor’s engineering team, watching over an OpenShift Container Platform environment and using its current state to make decisions in real time."
      link "https://docs.openshift.com/container-platform/${cv}/support/troubleshooting/troubleshooting-operator-issues.html"
      codeblock
      oc get clusteroperators --no-headers |awk '$3 == "False"' >> ${adoc}
      if (( $(oc get clusteroperators --no-headers | awk '$3 == "False"' | wc -l ) > 0 ))
      then 
         table "Unavailable Cluster Operators" "FAIL"
      else
         table "Unavailable Cluster Operators" "PASS"
      fi
      codeblock
   }

   cluster_services(){
      sub "Cluster Services Versions"
      quote "A cluster service version (CSV), is a YAML manifest created from Operator metadata that assists Operator Lifecycle Manager (OLM) in running the Operator in a cluster."
      link "https://docs.openshift.com/container-platform/${cv}/operators/operator_sdk/osdk-generating-csvs.html"
      codeblock 
      oc get clusterserviceversion -A -o wide --no-headers | awk '{print $2}' | sort | uniq  >> ${adoc}
      codeblock 
      table "Cluster Services Versions" "REVIEW"
   }

   operatorgroups(){
      sub "Operator Groups"
      quote "An Operator group, defined by the OperatorGroup resource, provides multitenant configuration to OLM-installed Operators. An Operator group selects target namespaces in which to generate required RBAC access for its member Operators."
      link "https://docs.openshift.com/container-platform/${cv}/operators/understanding/olm/olm-understanding-operatorgroups.html"
      codeblock 
      oc get operatorgroups -A 2>/dev/null >> ${adoc}
      codeblock 
      table "Operator Groups" "REVIEW"
   }

   operatorsources(){
      sub "Operator Sources"
      codeblock 
      oc get operatorsources -A 2>/dev/null  >> ${adoc}
      codeblock 
      table "Operator Sources" "REVIEW"
   }

   # Includes 
   operators_degraded
   operators_unavailable
   cluster_services
   operatorgroups
   operatorsources
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
         codeblock 
         oc get servicemeshcontrolplane -A 2>/dev/null  >> ${adoc}
         codeblock 
         table "Service Mesh ControlPlane" "REVIEW"
      fi
   }

   serviceMeshMember(){
      if [ cont == 'true' ]
      then
         sub "Service Mesh Members"
         codeblock
         oc get servicemeshmember -A 2>/dev/null  >> ${adoc}
         codeblock 
         table "Service Mesh Members" "REVIEW"
      fi
   }

   serviceMeshMemberRoll(){
      if [ cont == 'true' ]
      then 
         sub "Service Mesh Member Rolls"
         codeblock 
         oc get servicemeshmemberroll -A 2>/dev/null  >> ${adoc}
         codeblock 
         table "Service Mesh Members Rolls" "REVIEW"
      fi
   }

   # Includes 
   serviceMeshControlPlane
   serviceMeshMember
   serviceMeshMemberRoll

}

applications(){
   title "Applications"

   deploy_demo_app(){
      sub "Application Deployment"
      codeblock
      state="PASS"
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
            state="FAIL"
         else
            echo "Application Deployment: SUCCESS!" >> ${adoc}
         fi
         # Delete Schrodinger's cat project
         oc delete project schrodingers-cat >> ${adoc}
      else
         echo "WARNING: Unable to create DEMO project!" >> ${adoc}
         state="FAIL"
      fi
      codeblock
      table "Application Deployment" ${state}
   }

   non_ready_deployments(){
      sub "Non-Ready Deployments"
      codeblock
      oc get deployment -A 2>/dev/null | grep -E "0/[0-9]|NAMESPACE" | column -t >> ${adoc}
      if (( $(oc get deployment -A 2>/dev/null | grep -E "0/[0-9]|NAMESPACE" | wc -l) > 0 ))
      then 
         table "Non-Ready Deployments" "FAIL"
      else 
         table "Non-Ready Deployments" "PASS"
      fi 
      codeblock
   }

   non_available_deployments(){
      sub "Unavailable Deployments"
      codeblock 
      oc get deployment -A | awk '$(NF-1)=="0" || $1=="NAMESPACE"' | column -t >> ${adoc}
      if (( $(oc get deployment -A | awk '$(NF-1)=="0" || $1=="NAMESPACE"' | wc -l) > 0 ))
      then 
         table "Unavailable Deployments" "FAIL"
      else 
         table "Unavailable Deployments" "PASS"
      fi 
      codeblock 
   }

   inactive_projects(){
      sub "Inactive projects"
      codeblock 
      oc get projects --no-headers | awk '$NF =! "Active"' >> ${adoc}
      codeblock
      if (( $(oc get projects --no-headers | awk '{$NF =! "Active"}' | wc -l) > 0 ))
      then 
         table "Inactive projects" "FAIL"
      else 
         table "Inactive projects" "PASS"
      fi 
   }

   failed_builds(){
      sub "Failed Builds"
      codeblock 
      oc get builds -A | awk '$5 =! "Complete"' >> ${adoc}
      if (( $(oc get builds -A | awk '{$5 =! "Complete"}' | wc -l) > 0 ))
      then 
         table "Failed Builds" "FAIL"
      else 
         table "Failed Builds" "PASS"
      fi
      codeblock 
   }

   # Includes 
   deploy_demo_app
   non_ready_deployments
   non_available_deployments
   inactive_projects
   failed_builds

   #TODO: Verify that installed applications are not using deprectated api versions
   # oc get apiservices.apiregistration.k8s.io 

}

main(){
   environment_setup
   executive_summary
   table      # Initializing the executive summary table
   commons
   nodes 
   machines
   etcd 
   pods 
   security
   storage 
   performance
   logging 
   monitoring  
   network 
   operators
   mesh
   applications 
   table close_table_now   # Closing and adding the executive summary table
   # generate_pdf
} 

main 

# EndOfScript
