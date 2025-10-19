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

podman run -d -p 5000:5000 --name registry registry:2

podman tag localhost/1:latest localhost:5000/esame_img:1

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


#NOTA ho disabilitato docker e containerd in modo da usare solo crio

#RICORDA di controllare gli IP indicati in kubeadm_kubelet_config.yaml
sudo kubeadm init --config kubeadm_kubelet_config.yaml --upload-certs

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

sudo kubeadm token create --print-join-command

in order to connect i had to disable the firewall (sudo ufw disable)
curl -v -k https://192.168.1.191:6443/healthz (returns ok) (IP obvously depends on current network settings)

kubectl get nodes
NAME           STATUS   ROLES           AGE     VERSION
alessiovalle   Ready    <none>          6m25s   v1.33.3
boss-plane     Ready    control-plane   16m     v1.33.3

-----per monitorare

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

            helm install kube-prometheus-stack --create-namespace --namespace kube-prometheus-stack prometheus-community/kube-prometheus-stack

kubectl -n kube-prometheus-stack get pods

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
