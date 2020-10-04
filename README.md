# Installing Ambassador, ArgoCD, and Tekton on Kubernetes

## Ambassador Setup

First, I set up Ambassador (with TLS) as my API gateway. Why? For two reasons:
* To expose the ArgoCD dashboard and API server
* To expose Tekton Trigger EventListener services, so that I could trigger a Tekton pipeline via a Webhook

I set up TLS on Ambassador using [Cert-Manager](https://cert-manager.io).

**1- Install Ambassador ≥v1.7.3**

To install Ambassador on your cluster, run the commands below:

```bash
kubectl apply -f https://www.getambassador.io/yaml/aes-crds.yaml && kubectl wait --for condition=established --timeout=90s crd -lproduct=aes && kubectl apply -f https://www.getambassador.io/yaml/aes.yaml && kubectl -n ambassador wait --for condition=available --timeout=90s deploy -lproduct=aes
```

Among other things, the installation will create an `ambassador` namespace, and Ambassador custom resources.

If all goes well, you should be able to hit the Ambassador page on your cluster. To get the load balancer IP, run the following command:

```bash
AMBASSADOR_IP=$(kubectl get -n ambassador service ambassador -o "go-template={{range .status.loadBalancer.ingress}}{{or .ip .hostname}}{{end}}")
```

And then open up a browser window with the following address: `http://$AMBASSADOR_IP,` replacing `$AMBASSADOR_IP` with the value from the command above.

**2- Install Cert-Manager v1.0.0**

To get started with our TLS setup, you first need to install `cert-manager` on your cluster, by running the commands below:

```bash
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.0.0/cert-manager.crds.yaml
helm repo add jetstack https://charts.jetstack.io && helm repo update
kubectl create ns cert-manager
helm install cert-manager --namespace cert-manager jetstack/cert-manager
```

Among other things, the installation will create a `cert-manager` namespace, and cert-manager custom resources.

**3- Configure FQDN on your cluster (AKS only)**

This step applies to setting up an FQDN on AKS only. You'll need to check your cloud service provider docs to find out how to set up DNS or FQDN on your cluster.

>Note: You'll need to have the Azure CLI installed, in order for the above to work. Instructions on how to install it can be found here. After your install the Azure CLI, you'll also have to have the Azure AKS CLI installed, by running: `az aks install-cli`

Check out the Microsoft reference docs [here](https://medium.com/r/?url=https%3A%2F%2Fdocs.microsoft.com%2Fen-us%2Fazure%2Faks%2Fingress-tls%23add-an-a-record-to-your-dns-zone) for more info on the FQDN setup below.

```bash
# Public IP address of your ingress controller
IP=$(kubectl get -n ambassador service ambassador -o "go-template={{range .status.loadBalancer.ingress}}{{or .ip .hostname}}{{end}}")
# Name to associate with public IP address
DNSNAME="some-cool-name"
# Get the resource-id of the public ip -> some delay here!!
PUBLICIPID=$(az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv)
# Update public ip address with DNS name
az network public-ip update --ids $PUBLICIPID --dns-name $DNSNAME
# Display the FQDN
FQDN=$(az network public-ip show --ids $PUBLICIPID --query "[dnsSettings.fqdn]" --output tsv)
```

Now you should be able to hit the Ambassador home page by going to `http://$FQDN`, where is `FQDN` is the value of the last command execution in the above snippet.

**4- Configure TLS on Ambassador**

First, we create the CertificateIssuer and Certificate, and create corresponding Service and Ambassador Mappings using [ambassador-tls-cert-issuer.yml](resources/ambassador-tls-cert-issuer.yml)

Be sure to replace the following values before applying to Kubernetes:
1. `<you@address.com>` should be replaced with your email address
2. `<my_fqdn_replace_me>` should be replaced with the FQDN value from Step 3

Now we can apply it to our Kubernetes cluster: 

```bash
kubectl apply -f resources/ambassador-tls-cert-issuer.yml
```

Let's check our pods to make sure everything is good:

```bash
kubectl get pods -n cert-manager
```

You should see a pod called `cert-manager-<XYZ123>`. 

You can peek into the logs by running:

```bash
kubectl logs cert-manager-<XYZ123>
```

Check to make sure that our Certificate was created correctly:

```bash
kubectl describe certificates ambassador-certs -n ambassador
```

This can take a few minutes to set up fully. When setup is completed, you should see Reason: Ready and Status: True as part of the describe output.

Next, check to make sure that your secrets have been created:

```bash
kubectl get secrets -n ambassador
```

You should see a secret called `ambassador-certs` of type `Kubernetes.io/tls`.

Finally, we update Ambassador so that it uses TLS, listens on port `443`, and redirect http requests to https using [ambassador-tls-ambassador-service.yml](resources/ambassador-tls-ambassador-service.yml)

Apply the file:

```bash
kubectl apply -f ambassador-tls-ambassador-service.yml
```

If all goes well, we should be able to check everything by going to `https://$FQDN`. This should now display your Ambassador homepage with a lock next to it. Now when you try to hit the HTTP version of the page, you should now be redirected to the HTTPS version of the page.

*References:*
* https://www.getambassador.io/docs/latest/howtos/cert-manager/
* https://auth0.com/blog/kubernetes-tutorial-managing-tls-certificates-with-ambassador/

## ArgoCD v1.7.6 Installation

This is where I got really stuck. The ArgoCD docs give you all sorts of instructions for exposing the dashboard and API server with all sorts of ingress controllers, but zilch for Ambassador. I pulled many hairs trying to get this setup right. And then, I found this great little miracle tool on the Ambassador site, the Ambassador Initalizer tool. It actually generated the configs that I needed. The funny thing is that I found this tool after some seriously desperate Googling, as a result of landing on this Medium article. LIFESAVER.

Don't worry…I won't be a jerk and make you scour the links to figure things out for yourself. I've got some code for you. 😊

**1- Install ArgoCD**

Run the commands below to install ArgoCD on your cluster:

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v1.7.6/manifests/install.yaml
```

Among other things, the installation will create an `argocd` namespace, and ArgoCD custom resources.

**2- Use some magic to use Ambassador to expose ArgoCD services**

I will now draw your attention to the magical file [argocd-ambassador.yml](resources/argocd-ambassador.yml)

In a nutshell, you basically need to:
* Create an Ambassador `host` definition
* Modify the ArgoCD `deployment` (specifically lines 45–47)
* Define a Ambassador `mapping` so that you can hit the service externally

>Note: [argocd-ambassador.yml](resources/argocd-ambassador.yml) is based on the YAML files generated by the [Ambassador Initializer Tool](https://app.getambassador.io/initializer/). The tool generated more than I needed, so I just plucked out the relevant stuff. Be sure to bookmark this tool, because it is friggin' handy!!

Apply the file:

```bash
kubectl apply -f argocd-ambassador.yml
```

If all goes well, you should now be able to hit the following URLs:
* https://$FQDN/argo-cd (Admin dashboard)
* https://$FQDN/argo-cd/swagger-ui (API reference)
* https://$FQDN/argo-cd/api/webook (Webhook URL)

**3- Install the ArgoCD CLI**

You'll need the CLI so that you can create repo links and apps and users and whatnot on ArgoCD. Yes, you can also do it on the GUI, but eeewww.

To install the CLI using Homebrew on Mac:

```bash
brew install argocd
```

For all you non-Mac folks, follow the instructions [here](https://medium.com/r/?url=https%3A%2F%2Fargoproj.github.io%2Fargo-cd%2Fcli_installation%2F).

**4- Login to ArgoCD and change the admin password**

To log in to ArgoCD, first get the argocd-server podname. This is the admin password for ArgoCD:

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2
```

Now login using `admin` as the username, and the value above as your password (you'll be prompted when you run the command below):

```bash
argocd login $FQDN --grpc-web-root-path /argo-cd
```

Aaaaand change your admin password right away. You'll be prompted to provide the old and new values:

```bash
argocd account update-password
```

## Tekton v0.16.0 and Tekton Triggers v0.8.1 Installation

Finally, we're ready to install Tekton! Tekton Triggers are not part of the main Tekton installation. We'll be installing both.

**1- Install Tekton & Tekton Triggers**

To install Tekton triggers, run the commands below:

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.16.0/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.8.1/release.yaml
```

Among other things, the installation will create a `tekton` namespace, and Tekton and Tekton Trigger custom resources.

**2- Configure persistent volume for Tekton**

We need this because Tekton needs temporary space to clone git repos and build Dockerfiles:

```bash
kubectl create configmap config-artifact-pvc \
--from-literal=size=10Gi \
--from-literal=storageClassName=manual \
-o yaml -n tekton-pipelines \
--dry-run=client | kubectl replace -f -
```

You can do fancier storage setups if you'd like. I haven't explored this yet, so I don't have any nuggets of wisdom. But if you're interested, be sure to check the Tekton docs on this subject here.

## That's It!

Congratulations! You've installed Ambassador with TLS, ArgoCD, and Tekton! It's time to celebrate!!