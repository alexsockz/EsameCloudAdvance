#REMBER TO RUN DOCKER WHEN YOU NEED TO USE KUBERNETES

alias k="kubectl"

minikube start --driver=docker --container-runtime=cri-o

helm install prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

-stuff to access grafana

kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
-  prom-operator

kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80

Forwarding from 127.0.0.1:3000 -> 3000
Forwarding from [::1]:3000 -> 3000

connect via http://localhost:3000/ user:admin pw:prom-operator

added prometheus as a data source
created new data dashboard
added as metrics query: 
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

#REINIZIO, MINIKUBE NON VA BENE ---------------------------------------------

ora uso kubeadm

prima salvo l'immagine dal vecchio esame:

docker save esame_img:1 -o esame_img.tar

podman load -i esame_img.tar

podman run -d -p 5000:5000 --name registry docker.io/library/esame_img:1

ho dovuto permettere il port forwarding:
sudo sysctl -w net.ipv4.ip_forward=1


sudo kubeadm init --config kubeadm_kubelet_config.yaml

The InitConfiguration type should be used to configure runtime settings, that in case of kubeadm init are the configuration of the bootstrap token and all the setting which are specific to the node where kubeadm is executed

The ClusterConfiguration type should be used to configure cluster-wide settings, including settings for:

    networking that holds configuration for the networking topology of the cluster; use it e.g. to customize Pod subnet or services subnet.

    etcd: use it e.g. to customize the local etcd or to configure the API server for using an external etcd cluster.

    kube-apiserver, kube-scheduler, kube-controller-manager configurations; use it to customize control-plane components by adding customized setting or overriding kubeadm default settings.

The KubeletConfiguration type should be used to change the configurations that will be passed to all kubelet instances deployed in the cluster. If this object is not provided or provided only partially, kubeadm applies defaults

i had various problems due to ip configurations, i decided to resort to standard ip's due to the fact i would have to keep track of all the addreses far controller server and apimanager, by default it uses 127.0.0.1 so i would use that.

i tried using a different image repository for the control plane but was a bad idea

doesn't work it needs a CNI

now to run it needs calico

ESEGUIRE OGNI VOLTA

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml plugin di rete


controlla control-plane

kubectl taint nodes --all node-role.kubernetes.io/control-plane-


kubectl --namespace monitoring get pods -l "release=monitoring"

helm uninstall monitoring -n monitoring || true
kubectl delete namespace monitoring --ignore-not-found=true

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace

OBBIETTIVO
mi serve un solo pod e vedere come si comporta


cercando di collegare un worker node attraverso

kubeadm join 127.0.0.1:6443 --token 26qruh.bwlux5cs4zxt90ni \
	--discovery-token-ca-cert-hash sha256:2720f853b54420625cfd5e7c75b82b9b6a5f6ae4096b6ed51f3dd257423c1aca

ho dovuto disattivare il firewall

--------------------------------------------------------------------------
ordine definitivo


docker save esame_img:1 -o esame_img.tar

sudo podman load -i esame_img.tar #IMPORTANTISSIMO AVERE SUDO PERCHÈ CRIO USA LA REGISTRY A LIVELLO ROOT, NON USER

podman run -d -p 5000:5000 --name registry docker.io/library/esame_img:1

  
#NOTA ho disabilitato docker e containerd in modo da usare solo crio

#RICORDA di controllare gli IP indicati in kubeadm_kubelet_config.yaml
sudo kubeadm init --config kubeadm_kubelet_config.yaml --upload-certs

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# IMPORTANTE PERCHè STO USANDO UNA VIRTUAL MACHINE PROBABILMENTE
# Le VM spesso hanno interfacce di rete multiple (NAT, bridge, host-only)
# Calico può confondersi su quale interfaccia usare
# Ecco perché IP_AUTODETECTION_METHOD=cidr=192.168.1.0/24 è stato essenziale
# Aggiungi la variabile d'ambiente al DaemonSet
kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=cidr=192.168.1.0/24

# Verifica che sia stata aggiunta
kubectl get daemonset calico-node -n kube-system -o yaml | grep IP_AUTODETECTION_METHOD
# Aspetta che si ricreino
kubectl get pods -n kube-system -l k8s-app=calico-node -w

sudo kubeadm token create --print-join-command

in order to connect i had to disable the firewall (sudo ufw disable) remember to enable ip foreward on all devices

curl -v -k https://192.168.1.92:6443/healthz (returns ok) (IP obvously depends on current network settings)

kubectl get nodes
NAME           STATUS   ROLES           AGE     VERSION
alessiovalle   Ready    <none>          6m25s   v1.33.3
boss-plane     Ready    control-plane   16m     v1.33.3

-----per monitorare

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack \
  --create-namespace \
  --namespace kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack
AGGIORNAMENT AL 27/10/2025
-----------------------------------
OUTPUT
NAME: kube-prometheus-stack
LAST DEPLOYED: Mon Oct 27 11:46:04 2025
NAMESPACE: kube-prometheus-stack
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace kube-prometheus-stack get pods -l "release=kube-prometheus-stack"

Get Grafana 'admin' user password by running:

  kubectl --namespace kube-prometheus-stack get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo

Access Grafana local instance:

  export POD_NAME=$(kubectl --namespace kube-prometheus-stack get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack" -oname)
  kubectl --namespace kube-prometheus-stack port-forward $POD_NAME 3000

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.
---------------------------------
kubectl -n kube-prometheus-stack get pods
---- branch (su pc fisso funziona ignora sotto)
{
il pod non sta andando per colpa di alcuni taint
Warning  FailedScheduling  30s (x2 over 5m43s)  default-scheduler  0/2 nodes are available: 
  1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 
  1 node(s) had untolerated taint {node.kubernetes.io/disk-pressure: }
devo aggiungere spazio alla vm, for some reason the vm wasn't using all available 23gb
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv

un container del pod di grafana continua a fallire, non riusciva ad instanziare un folder 

helm install kube-prometheus-stack --create-namespace --namespace kube-prometheus-stack prometheus-community/kube-prometheus-stack --set grafana.securityContext.runAsUser=472

  export POD_NAME=$(kubectl --namespace kube-prometheus-stack get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack" -oname)
  kubectl --namespace kube-prometheus-stack port-forward $POD_NAME 3000

devo fornire al pod il file hpccinf.txt per sapere come fare il test:

kubectl create configmap hpccinf-file --from-file=hpccinf.txt=/home/alessiovalle/gitRepos/EsameCloudAdvance/data/hpccinf.txt

CAMBIO CNI 

curl https://raw.githubusercontent.com/projectcalico/calico/v3.30.2/manifests/canal.yaml -O

kubectl apply -f canal.yaml

#per poter rendere accedibile il registry al container runtime devo metterlo nel file config 

sudo nano /etc/containers/registries.conf

[[registry]]
location = "localhost:5000"
insecure = true

kubectl create configmap hpccinf-file --from-file=hpccinf.txt=/home/alessiovalle/gitRepos/EsameCloudAdvance/data/hpccinf.txt


kubectl apply -f EX2_deployment.yaml

PER CONTROLLARE SE IL CONFIG è ATTIVO 
kubectl config view

}

#############################################################

kubeprometheus su pc fisso FUNZIONA


helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
"prometheus-community" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "prometheus-community" chart repository
Update Complete. ⎈Happy Helming!⎈

░▒▓ 🎩  …/EsameCloudAdvance    main !  ▓▒░ ◦•········•◦ ░▒▓   3s776ms ▓▒░
··• helm install kube-prometheus-stack \
  --create-namespace \
  --namespace kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack
NAME: kube-prometheus-stack
LAST DEPLOYED: Mon Oct 27 11:46:04 2025
NAMESPACE: kube-prometheus-stack
STATUS: deployed
REVISION: 1
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace kube-prometheus-stack get pods -l "release=kube-prometheus-stack"

Get Grafana 'admin' user password by running:

  e

Access Grafana local instance:

  export POD_NAME=$(kubectl --namespace kube-prometheus-stack get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack" -oname)
  kubectl --namespace kube-prometheus-stack port-forward $POD_NAME 3000

Visit https://github.com/prometheus-operator/kube-prometheus for instructions on how to create & configure Alertmanager and Prometheus instances using the Operator.

░▒▓ 🎩  …/EsameCloudAdvance    main !  ▓▒░ ◦•·······•◦ ░▒▓   30s654ms ▓▒░
··•   kubectl --namespace kube-prometheus-stack get pods -l "release=kube-prometheus-stack"
NAME                                                        READY   STATUS    RESTARTS   AGE
kube-prometheus-stack-kube-state-metrics-557fd457c6-dx95x   1/1     Running   0          6m10s
kube-prometheus-stack-operator-566c866bf9-d77ln             1/1     Running   0          6m10s
kube-prometheus-stack-prometheus-node-exporter-5t8mg        1/1     Running   0          6m10s
kube-prometheus-stack-prometheus-node-exporter-mfdkl        1/1     Running   0          6m10s

░▒▓ 🎩  …/EsameCloudAdvance    main !  ▓▒░ ◦•···········•◦ ░▒▓   54ms ▓▒░
··•   kubectl --namespace kube-prometheus-stack get secrets kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d ; echo
prom-operator

░▒▓ 🎩  …/EsameCloudAdvance    main !  ▓▒░ ◦•···········•◦ ░▒▓   53ms ▓▒░
··• export POD_NAME=$(kubectl --namespace kube-prometheus-stack get pod -l "app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack" -oname)

ORA DEVO ESPORRE 3030 PER POTER MOSTRARE GRAFANA E 9090 PER VEDERE PROMETHEUS E OTTENERE I DATI

kubectl --namespace kube-prometheus-stack port-forward --address 0.0.0.0 $POD_NAME 3000
Forwarding from 0.0.0.0:3000 -> 3000

kubectl port-forward -n kube-prometheus-stack svc/kube-prometheus-stack-prometheus --address 0.0.0.0 9090
Forwarding from 0.0.0.0:9090 -> 9090

0.0.0.0 PERCHè COSI POSSO ACCEDERCI DA PORTATILE E OTTENERE LE INFORMAZIONI

poi devo andare in connections>data sources e aggiungere prometheus come data source su un ip fisso (ovvero 192.168.1.92:9090)


andrò a monitorare 
Home > Dashboards > Node Exporter / Nodes
per vedere il workload sui due nodi e vedere come kubernetes distribuisce il load


creo namespace dedicato per meglio monitorare:
kubectl create namespace hpl-test


<!-- You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of control-plane nodes by copying certificate authorities
and service account keys on each node and then running the following as root:

  kubeadm join 127.0.0.1:6443 --token 26qruh.bwlux5cs4zxt90ni \
	--discovery-token-ca-cert-hash sha256:2720f853b54420625cfd5e7c75b82b9b6a5f6ae4096b6ed51f3dd257423c1aca \
	--control-plane 

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 127.0.0.1:6443 --token 26qruh.bwlux5cs4zxt90ni \
	--discovery-token-ca-cert-hash sha256:2720f853b54420625cfd5e7c75b82b9b6a5f6ae4096b6ed51f3dd257423c1aca  -->



#SOLUZIONE PROBLEMA IMMAGINE
docker login

USING WEB-BASED LOGIN

i Info → To sign in with credentials on the command line, use 'docker login -u <username>'
         

Your one-time device confirmation code is: NZVQ-HZXX
Press ENTER to open your browser or submit your device code here: https://login.docker.com/activate

Waiting for authentication in the browser…


WARNING! Your credentials are stored unencrypted in '/home/alessiov/.docker/config.json'.
Configure a credential helper to remove this warning. See
https://docs.docker.com/go/credential-store/

Login Succeeded

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·····························································•◦ ░▒▓   54s112ms ▓▒░
··• crictl images | grep esame_img
FATA[0000] validate service connection: validate CRI v1 image API for endpoint "unix:///var/run/crio/crio.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/crio/crio.sock: connect: permission denied" 

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·································································•◦ ░▒▓   18ms ▓▒░
··• sudo crictl images | grep esame_img
[sudo] password di alessiov: 
docker.io/library/esame_img               1                   d022c5328e7a0       1.08GB
localhost/esame_img                       1                   d022c5328e7a0       1.08GB
localhost:5000/esame_img                  1                   d022c5328e7a0       1.08GB

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•······························································•◦ ░▒▓   2s176ms ▓▒░
··• podman tag docker.io/library/esame_img alessiovalle/esame_img:1
Error: docker.io/library/esame_img: image not known

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·································································•◦ ░▒▓   39ms ▓▒░
··• podman tag docker.io/library/esame_img:1 alessiovalle/esame_img:1

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·································································•◦ ░▒▓   51ms ▓▒░
··• podman alessiovalle/esame_img:1
Error: unrecognized command `podman alessiovalle/esame_img:1`
Try 'podman --help' for more information

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·································································•◦ ░▒▓   24ms ▓▒░
··• podman push alessiovalle/esame_img:1
Getting image source signatures
Error: trying to reuse blob sha256:a8346d259389bc6221b4f3c61bad4e48087c5b82308e8f53ce703cfc8333c7b3 at destination: unable to retrieve auth token: invalid username/password: unauthorized: incorrect username or password

··• docker ps
Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·································································•◦ ░▒▓   16ms ▓▒░
··• docker ls
docker: unknown command: docker ls

Run 'docker --help' for more information

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•·································································•◦ ░▒▓   13ms ▓▒░
··• podman login
Username: ^C
░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•······························································•◦ ░▒▓   3s166ms ▓▒░
··• podman login docker.io
Authenticating with existing credentials for docker.io
Existing credentials are valid. Already logged in to docker.io

░▒▓ 🎩  …/EsameCloudAdvance    main !?  ▓▒░ ◦•······························································•◦ ░▒▓   1s934ms ▓▒░
··• podman push alessiovalle/esame_img:1

kubectl describe pod hpl-single 

kubectl logs hpl-single

PRIMA DI QUESTO DEVI CREARE LA CONFIG MAP:

kubectl create -f single_pod.yaml -n hpl-test 
kubectl logs hpl-single -n hpl-test 
kubectl describe pod hpl-single -n hpl-test 

per cercare di dare il file hpccinf al pod ho cercato di usare un persistent volume ma non posso perchè indica una cartella su una macchina specifica, devo fare una config map

ho creato un file config_map.yaml
l'alternativa per linkare effettivamente il file è usare la linea di comando con 

kubectl create configmap hpccinf-config \
  --from-file=hpccinf.txt=/path/al/tuo/file/hpccinf.txt \
  -n hpl-test


ma io 


kubectl apply -f config_map.yaml -n hpl-test




NB servono 4 cpu per far andare hpcc
ho dato 3 cpu al nodo ora ho questo problema

  Warning  FailedScheduling  62s   default-scheduler  0/2 nodes are available: 1 Insufficient cpu, 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }. preemption: 0/2 nodes are available: 1 No preemption victims found for incoming pod, 1 Preemption is not helpful for scheduling.


quindi non ho nodi disponibili con abbastanza cpu

devo togliere il taint dal master node o rifare la vm
rifaccio la vm

SONO UN COGLIONE 4 PROCESSI NON CPU
BASTA MODIFICARE SUL DEPLOYMENT


COSA SIMPATICA CHE DIMOSTRA LA RESILIENZA DI KUBERNETES
mi è salata la corrente e sia vm che computer si sono spenti, questo ha causato al server kubernets di spegnersi, ciò nonostante il pod era deployato e appena l'ho riacceso sono stati subito redeployati (vedi dalle 13:45 alle 15:45)

Sono riuscito a fare  funzionare il multpod, primo tentativo 3 pod sullo stesso nodo con 4 processi, un pod può contenere 2 processi, gli altri 1, per un totale di 4, il minimo per hpcc.
i pod sono limitati in dimensioni, poi dovrò fare un test senza limiti, ovviamente non superano i limiti forniti

secondo test, ho messo un pod in più, quest'ultimo non riesce ad inizializzarsi e quindi il job fallisce perchè lo stateful set non è redy, e quindi non può essere utilizza, non so perchè da capire, anche perchè ho abbastanza memoria e nodi disponibili, ho bisogno di o piu potenza o un nuovo nodo, ho aggiunto un nodo

il nodo si unisce correttamente e lo stateful set riesce a diventare ready, una volta ready posso rilanciare il job e reinizia correttamente 

da notare che dato che
# ConfigMap for MPI hostfile
apiVersion: v1
kind: ConfigMap
metadata:
  name: mpi-hostfile
  namespace: hpl-test
data:
  hostfile: |
    hpl-worker-0.hpl-cluster.hpl-test.svc.cluster.local slots=2
    hpl-worker-1.hpl-cluster.hpl-test.svc.cluster.local slots=1
    hpl-worker-2.hpl-cluster.hpl-test.svc.cluster.local slots=1
    hpl-worker-3.hpl-cluster.hpl-test.svc.cluster.local slots=1
---

ho 2 slots nel primo e 1 negli altri, questo porta mpirun a mettere 2 processi nel primo pod nonostante più risorse siano ottenibili distribuendoli


