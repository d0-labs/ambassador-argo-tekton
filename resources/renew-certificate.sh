#!/bin/bash

## This is a script for renewing the Let's Encrypt Certificate managed by cert-manager. Run this when your certificate is about to expire,
## or as part of a job that runs every 60 or 80 days or so. Let's Encrypt Certificates expire every 90 days.

set -e

export CERT_NAME=$(kubectl get certificates -n ambassador -o name | cut -d'/' -f 2)
export ORIGINAL_CERT_EXPIRY=$(kubectl get certificate -n ambassador -o=jsonpath='{.items[0].status.notAfter}')
echo "Certificate expires on $ORIGINAL_CERT_EXPIRY"
export ORIGINAL_CERT_EXPIRY_DATE=$(date -j -f "%F" $ORIGINAL_CERT_EXPIRY +"%s")
kubectl delete certificate $CERT_NAME -n ambassador

export AMBASSADOR_CERTS_SECRET=$(kubectl get secrets -n ambassador -o=jsonpath='{.items[0].metadata.name}')
kubectl delete secret $AMBASSADOR_CERTS_SECRET -n ambassador

export CERT_MANAGER_POD_NAME=$(kubectl get pods -n cert-manager -o=jsonpath='{.items[0].metadata.name}')
echo Pod name: $CERT_MANAGER_POD_NAME

# See: https://gist.github.com/avillela/d220ad085502eb475ab6415b8b4ad208
kubectl apply -f cluster_setup/ambassador-tls-cert-issuer.yml

echo "Sleeping for 40 seconds to give the certificate time to generate"
sleep 40

kubectl describe certificates ambassador-certs -n ambassador
export NEW_CERT_EXPIRY=$(kubectl get certificate -n ambassador -o=jsonpath='{.items[0].status.notAfter}')
echo "New Certificate expires on $NEW_CERT_EXPIRY"
export NEW_CERT_EXPIRY_DATE=$(date -j -f "%F" $NEW_CERT_EXPIRY +"%s")

# https://unix.stackexchange.com/questions/84381/how-to-compare-two-dates-in-a-shell
if [ $NEW_CERT_EXPIRY_DATE -ge $ORIGINAL_CERT_EXPIRY_DATE ];
then
    echo "Success! New certificate generated. New expiry date is $NEW_CERT_EXPIRY"
else
    echo "***ERROR!! Expiry date not updated. Old expiry date: $ORIGINAL_CERT_EXPIRY. New expiry date: $NEW_CERT_EXPIRY"
    exit 1
fi

export SECERT_NAME=$(kubectl get secrets -n ambassador ambassador-certs -o name)
if [ "$SECERT_NAME" == "secret/ambassador-certs" ];
then
    echo "Secret $SECRET_NAME created."
else
    echo "Missing secret"
    exit 1
fi
