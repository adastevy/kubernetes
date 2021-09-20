---
title: "部署 kube-apiserver 组件"
date: 2019-03-16T16:24:24+08:00
draft: false
---

#### 创建 kubernetes 证书和私钥  
***创建证书签名请求：***
```
export  CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"
cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "192.168.10.232",
    "192.168.10.243",
    "192.168.10.242",
    "${CLUSTER_KUBERNETES_SVC_IP}",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "4Paradigm"
    }
  ]
}
EOF
```

***PS:***
```
hosts 字段指定授权使用该证书的 IP 或域名列表，这里列出了 apiserver 节点 IP、kubernetes 服务 IP 和域名,VIP暂时不需要；
域名最后字符不能是 . (如不能为 kubernetes.default.svc.cluster.local.)，否则解析时失败，提示： x509: cannot parse dnsName "kubernetes.default.svc.cluster.local."；
如果使用非 cluster.local 域名，如 opsnull.com，则需要修改域名列表中的最后两个域名为：kubernetes.default.svc.opsnull、kubernetes.default.svc.opsnull.com
kubernetes 服务 IP 是 apiserver 自动创建的，一般是 --service-cluster-ip-range 参数指定的网段的第一个IP，后续可以通过如下命令获取：
  $ kubectl get svc kubernetes
  NAME         CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
  kubernetes   10.254.0.1   <none>        443/TCP   1d
```

***生成证书和私钥：***  
```
cfssl gencert -ca=/etc/kubernetes/cert/ca.pem \
  -ca-key=/etc/kubernetes/cert/ca-key.pem \
  -config=/etc/kubernetes/cert/ca-config.json \
  -profile=kubernetes kubernetes-csr.json | cfssljson -bare kubernetes
ls kubernetes*pem
```
将生成的证书和私钥文件拷贝到 master 节点：
```
# cp kubernetes*.pem /etc/kubernetes/cert/
# chown -R k8s /etc/kubernetes/cert/
```
----

#### 创建 kube-apiserver systemd unit 模板文件
```
export ETCD_ENDPOINTS="https://192.168.10.232:2379"
export NODE_PORT_RANGE="30000-60000"
export SERVICE_CIDR="10.254.0.0/16"

cat > kube-apiserver.service.template <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=/opt/k8s/bin/kube-apiserver \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --anonymous-auth=false \\
  --advertise-address=##NODE_IP## \\
  --bind-address=##NODE_IP## \\
  --insecure-port=0 \\
  --authorization-mode=Node,RBAC \\
  --runtime-config=api/all \\
  --enable-bootstrap-token-auth \\
  --service-cluster-ip-range=${SERVICE_CIDR} \\
  --service-node-port-range=${NODE_PORT_RANGE} \\
  --tls-cert-file=/etc/kubernetes/cert/kubernetes.pem \\
  --tls-private-key-file=/etc/kubernetes/cert/kubernetes-key.pem \\
  --client-ca-file=/etc/kubernetes/cert/ca.pem \\
  --kubelet-client-certificate=/etc/kubernetes/cert/kubernetes.pem \\
  --kubelet-client-key=/etc/kubernetes/cert/kubernetes-key.pem \\
  --service-account-key-file=/etc/kubernetes/cert/ca-key.pem \\
  --etcd-cafile=/etc/kubernetes/cert/ca.pem \\
  --etcd-certfile=/etc/kubernetes/cert/kubernetes.pem \\
  --etcd-keyfile=/etc/kubernetes/cert/kubernetes-key.pem \\
  --etcd-servers=${ETCD_ENDPOINTS} \\
  --enable-swagger-ui=true \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/kube-apiserver-audit.log \\
  --event-ttl=1h \\
  --alsologtostderr=true \\
  --logtostderr=false \\
  --log-dir=/var/log/kubernetes \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
User=k8s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
```
***PS：***
```
--experimental-encryption-provider-config：启用加密特性；
--authorization-mode=Node,RBAC： 开启 Node 和 RBAC 授权模式，拒绝未授权的请求；
--enable-admission-plugins：启用 ServiceAccount 和 NodeRestriction；
--service-account-key-file：签名 ServiceAccount Token 的公钥文件，kube-controller-manager 的 --service-account-private-key-file 指定私钥文件，两者配对使用；
--tls-*-file：指定 apiserver 使用的证书、私钥和 CA 文件。--client-ca-file 用于验证 client (kue-controller-manager、kube-scheduler、kubelet、kube-proxy 等)请求所带的证书；
--kubelet-client-certificate、--kubelet-client-key：如果指定，则使用 https 访问 kubelet APIs；需要为证书对应的用户(上面 kubernetes*.pem 证书的用户为 kubernetes) 用户定义 RBAC 规则，否则访问 kubelet API 时提示未授权；
--bind-address： 不能为 127.0.0.1，否则外界不能访问它的安全端口 6443；
--insecure-port=0：关闭监听非安全端口(8080)；
--service-cluster-ip-range： 指定 Service Cluster IP 地址段；
--service-node-port-range： 指定 NodePort 的端口范围；
--runtime-config=api/all=true： 启用所有版本的 APIs，如 autoscaling/v2alpha1；
--enable-bootstrap-token-auth：启用 kubelet bootstrap 的 token 认证；
--apiserver-count=3：指定集群运行模式，多台 kube-apiserver 会通过 leader 选举产生一个工作节点，其它节点处于阻塞状态；
User=k8s：使用 k8s 账户运行；
```
----
#### 为各节点创建和分发 kube-apiserver systemd unit 文件  
我们只用master01，替换模板文件中的变量，为各节点创建 systemd unit 文件：
```
export NODE_IP="192.168.10.232"
sed -e "s/##NODE_IP##/${NODE_IP}/" kube-apiserver.service.template > kube-apiserver-${NODE_IP}.service
cp kube-apiserver-${NODE_IP}.service /etc/systemd/system/kube-apiserver.service
```
***PS:***
```
必须先创建日志目录；
文件重命名为 kube-apiserver.service;
```
-----
#### 启动 kube-apiserver 服务
```
# systemctl daemon-reload && systemctl enable kube-apiserver && systemctl restart kube-apiserver
```
-----
#### 打印 kube-apiserver 写入 etcd 的数据
```
ETCDCTL_API=3 etcdctl \
    --endpoints=${ETCD_ENDPOINTS} \
    --cacert=/etc/kubernetes/cert/ca.pem \
    --cert=/etc/etcd/cert/etcd.pem \
    --key=/etc/etcd/cert/etcd-key.pem \
    get /registry/ --prefix --keys-only
```
----
#### 检查集群信息
```
[root@master01 ~]# kubectl cluster-info
Kubernetes master is running at https://192.168.10.232:6443

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
[root@master01 ~]# kubectl get all --all-namespaces
NAMESPACE   NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
default     service/kubernetes   ClusterIP   10.254.0.1   <none>        443/TCP   12m
[root@master01 ~]# kubectl get componentstatuses
NAME                 STATUS      MESSAGE                                                                                     ERROR
scheduler            Unhealthy   Get http://127.0.0.1:10251/healthz: dial tcp 127.0.0.1:10251: connect: connection refused   
controller-manager   Unhealthy   Get http://127.0.0.1:10252/healthz: dial tcp 127.0.0.1:10252: connect: connection refused   
etcd-0               Healthy     {"health":"true"}                                                                           
[root@master01 ~]#
```
***PS:***

如果执行 kubectl 命令式时输出如下错误信息，则说明使用的 ~/.kube/config 文件不对，请切换到正确的账户后再执行该命令：
The connection to the server localhost:8080 was refused - did you specify the right host or port?
执行 kubectl get componentstatuses 命令时，apiserver 默认向 127.0.0.1 发送请求。当 controller-manager、scheduler 以集群模式运行时，有可能和 kube-apiserver 不在一台机器上，这时 controller-manager 或 scheduler 的状态为 Unhealthy，但实际上它们工作正常。

#### 授予 kubernetes 证书访问 kubelet API 的权限
在执行 kubectl exec、run、logs 等命令时，apiserver 会转发到 kubelet。这里定义 RBAC 规则，授权 apiserver 调用 kubelet API。
```
$ kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes
```
