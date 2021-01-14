#!/bin/bash

## This is a script for renewing the Let's Encrypt Certificate managed by cert-manager. Run this when your certificate is about to expire,
## or as part of a job that runs every 60 or 80 days or so. Let's Encrypt Certificates expire every 90 days.

set -e

# Delete the Certificate and its accompanying Secret
export CERT_NAME=$(kubectl get certificates -n ambassador -o name | cut -d'/' -f 2)
export ORIGINAL_CERT_EXPIRY=$(kubectl get certificate -n ambassador -o=jsonpath='{.items[0].status.notAfter}')
echo "Certificate expires on $ORIGINAL_CERT_EXPIRY"

# Use date -d if you're using non-BSD/MacOS
export ORIGINAL_CERT_EXPIRY_DATE=$(date -j -f "%F" $ORIGINAL_CERT_EXPIRY +"%s")

kubectl delete certificate $CERT_NAME -n ambassador

export AMBASSADOR_CERTS_SECRET=$(kubectl get secrets -n ambassador -o=jsonpath='{.items[0].metadata.name}')
kubectl delete secret $AMBASSADOR_CERTS_SECRET -n ambassador

# Just for kicks
export CERT_MANAGER_POD_NAME=$(kubectl get pods -n cert-manager -o=jsonpath='{.items[0].metadata.name}')
echo Pod name: $CERT_MANAGER_POD_NAME

# The only resource that should change when you apply this file is the Certificate, as it will be re-created
kubectl apply -f cluster_setup/ambassador-tls-cert-issuer.yml

# May take a bit of time for the certificate to generate. Putting in a pause.
echo "Sleeping for 40 seconds to give the certificate time to generate"
sleep 40

# Get our new certificat's expiry date
# Use date -d if you're using non-BSD/MacOS
kubectl describe certificates ambassador-certs -n ambassador
export NEW_CERT_EXPIRY=$(kubectl get certificate -n ambassador -o=jsonpath='{.items[0].status.notAfter}')
echo "New Certificate expires on $NEW_CERT_EXPIRY"
export NEW_CERT_EXPIRY_DATE=$(date -j -f "%F" $NEW_CERT_EXPIRY +"%s")

# We want to make sure that the new certificate's expiry date is after our old certificate's expiry date
if [ $NEW_CERT_EXPIRY_DATE -ge $ORIGINAL_CERT_EXPIRY_DATE ];
then
    echo "Success! New certificate generated. New expiry date is $NEW_CERT_EXPIRY"
else
    echo "***ERROR!! Expiry date not updated. Old expiry date: $ORIGINAL_CERT_EXPIRY. New expiry date: $NEW_CERT_EXPIRY"
    exit 1
fi

# Let's make sure that the secret accompanying our certificate was also created
export SECERT_NAME=$(kubectl get secrets -n ambassador ambassador-certs -o name)
if [ "$SECERT_NAME" == "secret/ambassador-certs" ];
then
    echo "Secret $SECRET_NAME created."
else
    echo "Missing secret"
    exit 1
fi
