#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

. $SCRIPT_DIR/bash-utils.sh
#. $SCRIPT_DIR/rhoai.env

export GO_VERSION=1.26.5 # need for make deploy
export GOROOT=/home/shuynh/go-${GO_VERSION}/go
export GOTOOLCHAIN=go${GO_VERSION}
export PATH=$GOROOT/go/bin:$PATH
export DOCKER_CONFIG=$HOME/.docker # for pull secret
export ODH_PLATFORM_TYPE=SelfManagedRHOAI
export OD_OPERATOR_NS=redhat-ods-operator
export OD_OPERATOR_DEPLOYMENT=rhods-operator
export OD_OPERATOR_SA=redhat-ods-operator-controller-manager
export OD_OPERATOR_LABEL="name=rhods-operator"

verify_od_op() {
  # Verify
  echo ""
  echo "INFO: --- verify_od_op ---"
  echo KUBECONFIG=$KUBECONFIG
  oc project
  cmd_run "oc get po -n $OD_OPERATOR_NS"
  cmd_run "oc get po -n $OD_OPERATOR_NS -o yaml | fgrep image"
  cmd_run "oc get deployment/$OD_OPERATOR_DEPLOYMENT -n $OD_OPERATOR_NS -o yaml |fgrep $ODH_PLATFORM_TYPE"
  cmd_run "oc get deployment/$OD_OPERATOR_DEPLOYMENT -n $OD_OPERATOR_NS -o yaml |fgrep image"
}

patch_od_op() {
  ns=$OD_OPERATOR_NS
  sa=$OD_OPERATOR_SA
  label=$OD_OPERATOR_LABEL

  cmd_run "oc set env deployment/$OD_OPERATOR_DEPLOYMENT -n $OD_OPERATOR_NS ODH_PLATFORM_TYPE=$ODH_PLATFORM_TYPE"
  cmd_run "oc set env deployment/$OD_OPERATOR_DEPLOYMENT -n $OD_OPERATOR_NS DISABLE_DSC_CONFIG=false"
  echo "oc create secret docker-registry rhoai-operator-pull-secret -n $ns --from-file=$DOCKER_CONFIG/config.json --dry-run=client -o yaml | oc apply -f -"
  oc create secret docker-registry rhoai-operator-pull-secret -n $ns --from-file=.dockerconfigjson=$DOCKER_CONFIG/config.json --dry-run=client -o yaml | oc apply -f -

  oc patch sa $sa -n $ns -p '{"imagePullSecrets": [{"name": "rhoai-operator-pull-secret"}]}' --type=merge

  cmd_run "oc delete pod -l $label -n $ns"
}

set_od_operator_image() {
  if [ "$branch_opt" == "rhoai-3.4" ]; then
    OD_OPERATOR_IMAGE=quay.io/rhoai/odh-rhel9-operator:rhoai-3.4
  elif [ "$branch_opt" == "rhoai-3.5-ea.1" ]; then
    OD_OPERATOR_IMAGE=quay.io/rhoai/odh-rhel9-operator:rhoai-3.5-ea.1
  elif [ "$branch_opt" == "rhoai-3.5-ea.2" ]; then
    OD_OPERATOR_IMAGE=quay.io/rhoai/odh-rhel9-operator:rhoai-3.5-ea.2
  elif [ "$branch_opt" == "rhoai-3.5" ]; then
    OD_OPERATOR_IMAGE=quay.io/rhoai/odh-rhel9-operator:rhoai-3.5
  elif [ "$branch_opt" == "rhoai-3.6-ea.1" ]; then
    OD_OPERATOR_IMAGE=quay.io/rhoai/odh-rhel9-operator:rhoai-3.6-ea.1
  fi
}	

install_op() {
  if [ "${branch_opt}" == '' ]; then
    echo "-b is required!"
    exit $EXIT_CODE
  else
    cmd_run "cd $OP_DIR"
    cmd_run "git checkout main && git pull"
    cmd_run "git branch"
    cmd_run "git checkout $branch_opt"
    if (( $? != 0 )); then
      exit $EXIT_CODE
    fi
    cmd_run "git pull"
    cmd_run "git branch"
    cmd_run "echo Make sure on right branch ... && sleep 5"
  fi

  set_od_operator_image $branch_opt
  cmd_run "echo Make sure the right image IMG=$OD_OPERATOR_IMAGE"
  cmd_run "sleep 5"
  cmd_run "ODH_PLATFORM_TYPE=$ODH_PLATFORM_TYPE make deploy IMG=$OD_OPERATOR_IMAGE"

  # Patch to pull image
  patch_od_op

  for ((i=1; i<=5; i++)); do
    verify_od_op
    sleep 3
  done
}

usage() {
  echo -e "Usage: "
  echo -e "  -b branch               -- required for install op. e.g: rhoai-3.4, rhoai-3.5-ea.2, rhoai-3.6-ea.1"
  echo -e "  -c install_op           -- deploy rhoai operator, need to set in rhoai.env, needs -b branch"
}

# if less than two arguments supplied, display usage
if [  $# -le 1 ]
then
  usage
  exit $EXIT_CODE
fi

while getopts "c:b:" flag
do
    case "${flag}" in
        b) branch_opt=${OPTARG};;
        c) command_opt=${OPTARG};;
    esac
done

if [ "${command_opt}" == 'install_op' ]; then
  install_op
else
  usage
fi
