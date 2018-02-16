#!/bin/bash

# precheck
oc whoami &> /dev/null
if [ $? -ne 0 ]; then
	echo 'Please login to a cluster before running this plugin. (e.g. oc login)'
	exit
fi

# initialize
TMP_DIR=$(mktemp -d --suffix=-openshift-sos-plugin)
DEST=$TMP_DIR/$KUBECTL_PLUGINS_CURRENT_NAMESPACE
mkdir -p $DEST

# Enable command logging
exec {BASH_XTRACEFD}>>$DEST/sos.log
set -x

# data capture
oc version &> $DEST/oc-version.txt
# Without -w, we cannot get full timestamps, so watch it and kill later
oc get event -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE -w &> $DEST/oc-get-event.txt &
WATCH_PID=$!
oc status -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE &> $DEST/oc-status.txt
oc get project -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE -o ${KUBECTL_PLUGINS_LOCAL_FLAG_OUTPUT} &> $DEST/oc-get-project.${KUBECTL_PLUGINS_LOCAL_FLAG_OUTPUT}
TARGET_OBJECTS="all,ds,pvc,hpa,quota,limits,sa,rolebinding"
if [ "$KUBECTL_PLUGINS_LOCAL_FLAG_INCLUDE_CONFIGMAP" == "true" ]; then
    TARGET_OBJECTS="$TARGET_OBJECTS,cm"
fi
if [ "$KUBECTL_PLUGINS_LOCAL_FLAG_INCLUDE_SECRET" == "true" ]; then
    TARGET_OBJECTS="$TARGET_OBJECTS,secret"
fi
oc get $TARGET_OBJECTS -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE -o ${KUBECTL_PLUGINS_LOCAL_FLAG_OUTPUT} &> $DEST/oc-get-all.${KUBECTL_PLUGINS_LOCAL_FLAG_OUTPUT}
oc get $TARGET_OBJECTS -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE -o wide &> $DEST/oc-get-all.txt
PODS=$(oc get pod -o name -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE)
for pod in $PODS; do
  CONTAINERS=$(oc get $pod --template='{{range .spec.containers}}{{.name}} {{end}}' -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE)
  for c in $CONTAINERS; do
    oc logs $pod --container=$c --timestamps -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE &> $DEST/${pod//\//-}_${c//\//-}.log
    oc logs -p $pod --container=$c --timestamps -n $KUBECTL_PLUGINS_CURRENT_NAMESPACE &> $DEST/${pod//\//-}_${c//\//-}.previous.log
  done
done
kill $WATCH_PID

# if we can access to non-namespaced objects, get additional info
if [ "$(oc policy can-i get nodes 2>/dev/null)" == "yes" ]; then
  oc get node -o wide &> $DEST/oc-get-node.txt
  oc get node -o ${KUBECTL_PLUGINS_LOCAL_FLAG_OUTPUT} &> $DEST/oc-get-node.${KUBECTL_PLUGINS_LOCAL_FLAG_OUTPUT}
  oc describe node &> $DEST/oc-describe-node.txt
  oc get hostsubnet &> $DEST/oc-get-hostsubnet.txt
  oc get clusterrolebindings &> $DEST/oc-get-clusterrolebindings.txt
fi

# compress
DEST_FILE=/tmp/oc-sos-${KUBECTL_PLUGINS_CURRENT_NAMESPACE}-$(date +%Y%m%d-%H%M%S).tar.xz
tar caf $DEST_FILE -C $TMP_DIR $KUBECTL_PLUGINS_CURRENT_NAMESPACE

echo "Data capture complete and archived in $DEST_FILE"

# cleanup
rm -r $TMP_DIR

