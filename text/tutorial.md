[TL;DR: Run Kubernetes on two micro instances on GKE with no external load balancer to save all the moneys.]

My excitement of running _kubernetes_ on Google Cloud Platform was quickly curbed by the realization that, despite Google's virtual machines starting at affordable price points, their network ingress is another story: Let's say you want to set up a simple cluster for your own personal projects, or a small business. At the time of writing, a couple of micro nodes running in Iowa will set you back $7.77/mo, but the only (officially marketed, AFAIK) method of getting traffic in is by using a load balancer - which start at whopping $18.26 for the first 5 forwarding rules. That is a deal breaker for me, since there are plenty of other cloud providers with better offerings to smaller players. 

That's when I stumbled upon a [great article](https://charlieegan3.com/posts/2018-08-15-cheap-gke-cluster-zero-loadbalancers/) about running a GKE cluster without load balancers. With this newly incited motivation, I set out to create my GKE cluster - with the requirement of it being as cheap as possible while enjoying a key benefit of the cloud: being free of manual maintenance. 

I have composed this article as a step-by-step tutorial. Based on my own experience in setting up a cluster on a fresh GCP account, I try to cover every topic from configuring the infrastructure to serving HTTP(S) requests from inside the cluster. Please notice, that I did this mainly to educate myself on the subject, so critique and corrections are wholeheartedly welcome.

Let’s get going by creating a new project on the GCP console:

##### Project selector (top bar) -> New Project -> Enter name -> Create

This will create a nice empty project for us, which differs from the default starter project in that the newly created blank doesn’t come with any predefined API’s or service accounts.
We’ll start digging our rabbit hole by enabling the Compute Engine API, which we need to communicate with GCP using Terraform.

##### APIs & Services -> API Library -> Compute Engine API -> Enable

Once the API has been initialized, we should find that GCP has generated a new service account for us. The aptly named Compute Engine default service account grants us remote access to the resources of our project.
Next, we’ll need to create a key for Terraform to authenticate with GCP:

##### IAM & Admin -> Service accounts -> Compute Engine default service account -> Create key -> Create as JSON

The key that we just downloaded can be used in our terraform.io console as an environment variable, or directly from local disk when running Terraform CLI commands. The former requires newlines edited out of the JSON file and the contents added as `GOOGLE_CLOUD_KEYFILE_JSON` in our terraform.io workspace:

##### Workspaces -> \<workspace\> -> Variables -> Environment Variables

Make sure you set the value as “sensitive / write only”, if you decide to store the key in your terraform.io workspace.
As stated above, it’s also possible to read the key from your local drive by adding the following in the Terraform provider resource:

```terraform
provider "google" {
  version = "3.4.0"
  credentials = file("<filename>.json")
}
```

In this tutorial, we’ll be using the latter of the two methods.

While we’re here, it’s worth noting that the Compute Engine default service account doesn’t have the permissions to create new roles and assign IAM policies in the project. This is something that we will need later as part of our terraforming process, so let’s get it over with:

##### IAM & admin -> edit Compute Engine default service account (pen icon) -> Add another role -> select "Role Administrator" -> Save

##### Add another role -> select "Project IAM Admin" -> Save

We’re now ready to initialize Terraform and apply our configuration to the cloud.

```shell
terraform init
```

This will set up your local Terraform workspace and download the Google provider plugin, which is used to configure GCP resources.

We can proceed to apply the configuration to our GCP project.

```shell
terraform apply
```

This will feed the configuration to the terraform.io cloud, check its syntax, check the state of our GCP project and, finally, ask for confirmation to apply our changes. Enter ‘yes’ and sit back. This is going to take a while.

```shell
module.cluster.google_project_iam_custom_role.kluster: Creating...
module.cluster.google_service_account.kluster: Creating..
module.cluster.google_compute_network.gke-network: Creating...
module.cluster.google_compute_address.static-ingress: Creating...
module.cluster.google_service_account.kubeip: Creating...
module.cluster.google_container_node_pool.custom_nodepool["ingress-pool"]: Creating...

module.cluster.google_container_node_pool.custom_nodepool["ingress-pool"]: Creation complete after 1m8s
```

Once the dust has settled, it’s time to check the damage. We set out to configure a minimal cloud infrastructure for running a _kubernetes_ cluster, so let’s see how we’ve managed so far.

##### Compute Engine -> VM Instances

This page reveals that we now have two virtual machines running. These machines are part of node pools ingress-pool and web-pool. A node pool is a piece of configuration, which tells Google Container Engine (GKE) how and when to scale the machines in our cluster up or down. You can find the node pool definitions in [cluster.tf](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L32) and [node_pool.tf](https://github.com/nkoson/gke-tutorial/blob/master/gke/node_pool.tf#L1)

If you squint, you can see that the machines have internal IP addresses assigned to them. These addresses are part of our [subnetwork](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L9) range. There is a bunch of other address ranges defined in our cluster, which we’ll glimpse over right now:

```terraform
subnet_cidr_range = "10.0.0.0/16"
# 10.0.0.0 -> 10.0.255.255
```

Defined in [google_compute_subnetwork](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L9), this is the address range of the subnetwork, in which our GKE cluster will run.

```terraform
master_ipv4_cidr_block = "10.1.0.0/28"
# 10.1.0.0 -> 10.1.0.15
```

The master node of our _kubernetes_ cluster will be running under this block, used by [google_container_cluster](https://github.com/nkoson/gke-tutorial/blob/master/gke/main.tf#L36).

```terraform
cluster_range_cidr = "10.2.0.0/16"
# 10.2.0.0 -> 10.2.255.255
```

Rest of our _kubernetes_ nodes will be running under this range, defined as a [secondary range](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L21) as part of our subnet.

```terraform
services_range_cidr = "10.3.0.0/16"
# 10.3.0.0 -> 10.3.255.255
```

Also a secondary range in our subnet, the service range contains our _kubernetes_ services, more of which a bit later.

Understanding the basic building blocks of our network, there are a couple more details that we need to grasp in order for this to make sense as a whole. The nodes in our cluster can communicate with each other on the subnet we just discussed, but what about incoming traffic? After all, we’ll need to not only accept incoming connections, but also download container images from the web. Enter Cloud NAT:

##### Networking -> Network Services -> Cloud NAT

Part of our router configuration, Cloud NAT grants our VM instances Internet connectivity without external IP addresses. This allows for a secure way of provisioning our _kubernetes_ nodes, as we can download container images through NAT without exposing the machines to public Internet.
In our [definition](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L40), we set the router to allow automatically allocated addresses and to operate only on our subnetwork, which we set up earlier.

OK, our NAT gives us outbound connectivity, but we’ll need a inbound address for our cheap-o load balancer / ingress / certificate manager all-in-one contraption, **Traefik**. We’ll talk about the application in a while, but let’s first make sure that our external static IP addresses are in check:

##### Networking -> VPC network -> External IP addresses

There should be two addresses on the list; an automatically generated one in use by our NAT, plus another, currently unused address which is named static-ingress. This is crucial for our cluster to accept connections without an external load balancer, since we can route traffic through to our ingress node using a static IP.
We’ll be running an application, kubeip, in our cluster to take care of assigning the static address to our ingress node, which we’ll discuss in a short while.

This is a good opportunity to take a look at our firewall settings:

##### Networking -> VPC network -> Firewall rules

We have added a single custom rule, which lets inbound traffic through to our ingress node. Notice, how we specify a target for the rule to match only with instances that carry the ingress-pool tag. After all, we only need HTTP(S) traffic to land on our internal load balancer (_Traefik_). The custom firewall rule is defined [here](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L76).

Lest we forget, one more thing: We'll be using the CLI tool **gcloud** to get our _kubernetes_ credentials up and running in the next step. Of course, _gcloud_ needs a configuration of its own, as well, so let's get it over with:

```shell
gcloud init
```

Answer truthfully to the questions and you shall be rewarded with a good gcloud config.

## Kubernetes

Our cloud infrastructure setup is now done and we're ready to run some applications in the cluster. In this tutorial, we'll be using **kubectl** to manage our kubernetes cluster. To access the cluster on GCP, kubectl needs a valid config, which we can quickly fetch by running:

```shell
gcloud container clusters get-credentials <cluster> --region <region>
```

### Aggressive optimizations

Disclaimer: I don't recommend doing any of the things I've done in this section. Feel free to crank up the [node pool machine types](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L32) to something beefier (such as g1-small) in favor of keeping logging and metrics alive. At the time of writing this tutorial, I had to make some rather aggressive optimizations on the cluster to run everything on two micro instances. We did mention being cheap, didn't we?

Realizing that it's probably not a good idea to disable logging, we have [disabled logging](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L29) on GCP. Now that we're up to speed, why don't we go ahead and turn off _kubernetes_ metrics as well:

```shell
kubectl scale --replicas=0 deployment/metrics-server-v0.3.1 --namespace=kube-system
```

That's over 100MB of memory saved on our nodes at the expense of not knowing the total memory and CPU consumption anymore. Sounds like a fair deal to me!
We'll scale kube-dns service deployments down as well, since running multiple DNS services in our tiny cluster seems like an overkill:

```shell
kubectl scale --replicas=0 deployment/kube-dns-autoscaler --namespace=kube-system
kubectl scale --replicas=1 deployment/kube-dns --namespace=kube-system
```

_kubernetes_ default-backend can go too. We'll be using **nginx** for this purpose:

```shell
kubectl scale --replicas=0 deployment/l7-default-backend --namespace=kube-system
```

At this point I realized that the instance spun up from **web-pool** was stuck at "ContainerCreating" with all the _kubernetes_ deployments I just disabled still running, so I just deleted the instance to give it a fresh start:

```shell
gcloud compute instances list
gcloud compute instances delete <name of the web-pool instance>
```

After a few minutes, GCP had spun up a new instance from the _web-pool_ instance pool, this time without the metrics server, default backend and with only one DNS service.

### Deployments

The cluster we're about to launch has three deployments: _nginx_ for serving web content, **kubeIP** for keeping our ingress node responsive and _Traefik_ which serves a dual purpose; routing incoming connections to _nginx_, plus handling SSL. We'll discuss each deployment next.

### nginx-web

Incoming HTTP(S) traffic in our cluster is redirected to the _nginx_ server, which we use as our web backend. Put simply in _kubernetes_ terms, we're going to **deploy** a container image within a **namespace** and send traffic to it through a **service**. We'll do namespace first. Navigate to `k8s/nginx-web/` and run:

```shell
kubectl create --save-config -f namespace.yaml
```

Pretty straightforward so far. The namespace we just created is defined [here](https://github.com/nkoson/gke-tutorial/blob/master/k8s/nginx-web/namespace.yaml#L1). Next up is the deployment:

```shell
kubectl create --save-config -f deployment.yaml
```

As you can see from the [definition](https://github.com/nkoson/gke-tutorial/blob/master/k8s/nginx-web/deployment.yaml#L5), we want our deployment to run under the namespace `nginx-web`. We need the container to run on a virtual machine that's spun up from the node pool [web-pool](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L46), hence the [nodeSelector](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L46) parameter. We're doing this because we want to run everything _except_ the load balancer on a preemptible VM to cut down costs while ensuring maximum uptime.

Moving on, the [container section](https://github.com/nkoson/gke-tutorial/blob/master/k8s/nginx-web/deployment.yaml#L23) defines a Docker image we want to run from our private Google Container Registry (GCR) repository. Below that, we open the ports 80 and 443 for traffic and set up health check (liveness probe) for our container. The cluster will now periodically GET the container at the endpoint _/health_ and force a restart if it doesn't receive a 200 OK response within the given time. Readiness probe is basically the same, but will tell the cluster when the container is ready to start accepting connections after initialization.

We won't dive too deep into Docker in this tutorial, but we have included a basic nginx:alpine container with placeholder web content in this tutorial. We'll need to upload the container image to GCR for _kubernetes_ to use it as per the deployment we just created. Navigate to `docker/nginx-alpine` and run:

```shell
docker build -t eu.gcr.io/<project>/nginx-web .
```

This builds the image and tags it appropriately for use in our cluster. We need docker to authenticate with GCP, so let's register gcloud as docker's credential helper by running:

```shell
gcloud auth configure-docker
```

To push the image into our registry, run:

```shell
docker push eu.gcr.io/<project>/nginx-web
```

We can check that everything went fine with the deployment by running:

```shell
kubectl get event --namespace nginx-web
```

```shell
LAST SEEN  TYPE      REASON              KIND   MESSAGE
1m         Normal    Pulling             Pod    pulling image "eu.gcr.io/gke-tutorial-xxxxxx/nginx-web:latest"
1m         Normal    Pulled              Pod    Successfully pulled image "eu.gcr.io/gke-tutorial-xxxxxx/nginx-web:latest"
1m         Normal    Created             Pod    Created container
1m         Normal    Started             Pod    Started container
```

We now have an _nginx_ container running in the right place, but we still need to route traffic to it within the cluster. This is done by creating a _service_ :

```shell
kubectl create --save-config -f service.yaml
```

Our [service definition](https://github.com/nkoson/gke-tutorial/blob/master/k8s/nginx-web/service.yaml#L2) is minimal: We simply route incoming traffic to applications that match the _selector_ `nginx-web`. In other words, traffic that gets sent to this service on ports 80 and 443 will get directed to pods running our web backend.

### kubeIP

Working in a cloud environment, we cannot trust that our virtual machines stay up infinitely. In contrary, we actually embrace this by running our web server on a _preemptible_ node. Preemptible nodes are cheaper to run, as long as we accept the fact that they go down for a period of time at least once a day.
We could easily ensure higher availability in our cluster by simply scaling up the number of nodes, but for the sake of simplicity, we'll stick to one of each type, defined by our node pools [ingress-pool](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L33) and [web-pool](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L46)

A node pool is a set of instructions on how many and what type of instances we should have running in our cluster at any given time. We'll be running _traefik_ on a node created from _ingress-pool_ and the rest of our applications run on nodes created from _web-pool_.

Even though the nodes from _ingress-pool_ are not preemptible, they might restart some time. Because our cheap-o cluster doesn't use an external load balancer (which is expen\$ive), we need to find another way to make sure that our ingress node always has the same IP for connectivity.
We solve this issue by creating a [static IP address](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L63) and using _kubeip_ to bind that address to our ingress node when necessary.

Let's create the deployment for _kubeip_ by navigating to `k8s/kubeip` and running:

```shell
kubectl create --save-config -f deployment.yaml
```

We define `kube-system` as the [target namespace](https://github.com/nkoson/gke-tutorial/blob/master/k8s/kubeip/deployment.yaml#L9) for _kubeip_, since we want it to communicate directly with the _kubernetes_ master and find out when a newly created node needs a static address. Using a [nodeselector](https://github.com/nkoson/gke-tutorial/blob/master/k8s/kubeip/deployment.yaml#L21), we force _kubeip_ to deploy on a _web-pool_ node, just like we did with _nginx_ earlier.

Next in the config we define a bunch of environment variables, which we bind to values in a _ConfigMap_. We instruct our deployment to fetch GCP service account credentials from a _kubernetes_ _secret_. Through the [service account](https://github.com/nkoson/gke-tutorial/blob/master/k8s/kubeip/deployment.yaml#L70), _kubeip_ can have the required access rights to make changes (assign IPs) in GCP.

We created a GCP [service account for kubeip](https://github.com/nkoson/gke-tutorial/blob/master/gke/iam.tf#L42) as part of our Terraform process. Now we just need to extract its credentials just like we did with our main service account in the beginning of this tutorial. For added variety, let's use the command line this time. From the root of our project, run:

```shell
gcloud iam service-accounts list
gcloud iam service-accounts keys create keys/kubeip-key.json --iam-account <kubeip service-account id>
```

Now that we have saved the key, we'll store it in the cluster as a _kubernetes_ secret:

```shell
kubectl create secret generic kubeip-key --from-file=keys/kubeip-key.json -n kube-system
```

We have created a GCP service account for _kubeip_ and configured _kubeip_ to access it via the _kubernetes_ secret. We will still need a _kubernetes service account_ to access information about the nodes in the cluster. Let's do that now:

```shell
kubectl create --save-config -f serviceaccount.yaml
```

We define a (_kubernetes_) [ServiceAccount](https://github.com/nkoson/gke-tutorial/blob/master/k8s/kubeip/serviceaccount.yaml#L3) and below it the _ClusterRole_ and _ClusterRoleBinding_ resources, which define what our service account is allowed to do and where.

Next, we need to create the _ConfigMap_ for the deployment of _kubeip_:

```shell
kubectl create --save-config -f configmap.yaml
```

In the [config](https://github.com/nkoson/gke-tutorial/blob/master/k8s/kubeip/configmap.yaml#L2), we set _kubeip_ to run in `web-pool` and watch instances spun up from `ingress-pool`. When _kubeip_ detects such an instance, it checks if there is an unassigned IP address with the [label](https://github.com/nkoson/gke-tutorial/blob/master/gke/network.tf#L70) _kubeip_ and value _static-ingress_ in the reserve and gives that address to the instance. We have restricted the `ingress-pool` to a single node, so we only need a single static IP address in our reserve.

### traefik

External load balancers are very useful in keeping your web service responsive under high load. They are also prohibitively expensive for routing traffic to that single pod in your personal cluster, so we're going to make do without one.

In our tutorial cluster, we dedicate a single node to hosting _traefik_, which we configure to route traffic to our web backend (_nginx_ server). _Traefik_ can also fetch SSL certificates from resolvers such as `letsencrypt` to protect our HTTPS traffic. We're not going to cover procuring a domain name and setting up DNS in this tutorial, but, for reference, I have left everything that's required for setting up a DNS challenge commented out in the code.

Let's create a namespace and a service account for _traefik_. Navigate to `k8s/traefik` and run:

```shell
kubectl create --save-config -f namespace.yaml
```

```shell
kubectl create --save-config -f serviceaccount.yaml
```

Next, we'll create the deployment and take a look at what we've done so far:

```shell
kubectl create --save-config -f deployment.yaml
```

Using a [nodeSelector](https://github.com/nkoson/gke-tutorial/blob/master/k8s/traefik/deployment.yaml#L23) once again, we specify that we want _traefik_ to run on a machine that belongs to `ingress-pool`, which means that in our cluster, _traefik_ will sit on a different machine than _kubeip_ and _nginx_. The thought behind this is that both of our machines are unlikely to go down simultaneously. When `web-pool` goes down and is restarted, no problem; _traefik_ will find it in the cluster and resume routing connections normally.
If our `ingress-pool` went down, the situation would be more severe, since we need our external IP bound to that machine. How else would our clients land on our web backend? Remember we don't have an external load balancer...
Luckily, we have _kubeip_ which will detect the recently rebooted `ingress-pool` machine and assign our external IP back to it in no time. Crisis averted!

There's a couple key things in our _traefik_ deployment that sets it apart from our other deployments. First is [hostNetwork](https://github.com/nkoson/gke-tutorial/blob/master/k8s/traefik/deployment.yaml#L22) which we need for _traefik_ to listen on network interfaces of its host machine.
Secondly, we define a [toleration](https://github.com/nkoson/gke-tutorial/blob/master/k8s/traefik/deployment.yaml#L25), because we have [tainted](https://github.com/nkoson/gke-tutorial/blob/master/cluster.tf#L63) the host node pool. Since our _traefik_ deployment is the only one with this toleration, we can rest assured that no other application is deployed on `ingress-pool`.

Finally, we give _traefik_ some [arguments](https://github.com/nkoson/gke-tutorial/blob/master/k8s/traefik/deployment.yaml#L40) : entry points for HTTP, HTTPS and health check (ping in _traefik_ lingo). We also enable the _kubernetes_ provider, which lets us use _custom resources_. Let's create them now:

```shell
kubectl create --save-config -f resource.yaml
```

Now we can add _routes_ to _traefik_ using our new custom resources:

```shell
kubectl create --save-config -f route.yaml
```

The two routes now connect the "web" and "websecure" entrypoints (which we set up as arguments for _traefik_) to our `nginx-web` service. We should now be able to see HTML content served to us by _nginx_ when we connect to our static IP address. 

Please enjoy your cluster-on-a-budget responsively!
