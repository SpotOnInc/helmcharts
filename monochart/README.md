# Monochart

## Introduction

Forked from [github.com/cloudposse/charts](https://github.com/cloudposse/charts/tree/master/incubator/monochart)

## Changes

### common.labels
We have changed the common.labels from:

|before|now|
|-|-|
|app=monochart|app.kubernetes.io/name=spoton-monochart
|app.kubernetes.io/managed-by=Helm|app.kubernetes.io/managed-by=Helm|
|chart=monochart-0.24.0|helm.sh/chart=spoton-monochart-1.1.1|
|heritage=Helm|
|release=restaurant-etl-dim-employee-staging|app.kubernetes.io/instance=emaster-pos-staging|

Following the recommendations from K8s:
https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/#labels


> Note: These labels are the default values, but we still need to add others labels in our helmfiles values, like:

|Others defaults values|
|-|
|app.kubernetes.io/version: "5.7.21"|
|app.kubernetes.io/component: database|
|app.kubernetes.io/part-of: restaurant|


### Initcontainers
We have add [InitContainers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/) template to this chart. It is disable by default, but when enable, the template will put everything inside of the **FirstInitContainer** parameter inside of the configuration.

If you need more than one InitContainer, you can use **extraInitContainer** parameter multiples times.

### SealedSecrets
[SealedSecrets](https://github.com/bitnami-labs/sealed-secrets) is a kubernetes controller that allows us to generate and encrypt secrets using TLS certificates (RSA 4096 bit by default) and not the default base64. With it, we can create secrets and manager/store it inside of the github repository.

This requires the sealedsecrets controller to be installed in the cluster first. The component to install for eks clusters is this one: https://github.com/SpotOnInc/infrastructure/blob/main/stacks/catalog/eks/cluster-services/sealed-secrets.yaml

For kops clusters, the right component to use is this one: https://github.com/SpotOnInc/infrastructure/blob/main/stacks/catalog/helm-sealed-secrets.yaml

To make sure a secret gets created before pod creation, use the extraAnnotations provided in the google-secrets example in the values.yaml.

To enable it on this chart you need to add this values to the helmfile.

```yaml
sealedsecrets:
  enabled: false
    keys:
    - name: google-secrets
      encryptedData:
        SECRET_NAME: AgSDSDSB7oTOgJ[...cut...]ZOggQH8gGkMQQ8p
        ANOTHER_SECRET: AgCSDSDSNGpjn39lO[...cut...]n5du/NmBa

envFrom:
    secrets:
    - google-secrets

VolumeMountsConfig: |
  - name: google-secrets
    secret:
      defaultMode: 420
      secretName: google-secrets

FirstVolumeMounts: |
  - mountPath: /google/secrets
    name: google-secrets
```

The first will create a **sealed secret** resource called google-secrets with two secrets (SECRET_NAME and ANOTHER_SECRET)... when deployed, kubernetes will use the private key to decipher this secrets and get the correct value.

The second, will setup this secret inside of the containers.

The third and fourth, will set up a volume using a volume mount, that will create a file inside of the pod for each secret defined under encrypedData. (using this example, we should get a file named SECRET_NAME with the unencrypted data as the content, and same for ANOTHER_SECRET. )

> Note: To generate you can use [kubeseal](https://github.com/bitnami-labs/sealed-secrets#installation-from-source) from CLI or you can use the Spoton [WebSeal](https://webseal.qa.spoton.sh/) interface.

An example of using kubeseal: (The sealedsecret.pub cert is obtained in the logs of the sealedsecrets controller)
```
kubeseal --cert sealedsecret.pub --scope cluster-wide --format yaml <unencrypted-secret.yaml >sealed-secret.yaml
```

### VolumeMounts
The actual VolumeMounts of the old-monochart version works, but not very well when we need to manage it with differents containers (ex: InitContainers). so, we have add 3 new parameters to improve it
* FirstVolumeMounts
* extraVolumeMounts
* VolumeMountsConfig

The **FirstVolumeMounts** and **extraVolumeMounts** will put the raw yaml from these parameters inside of the containers. for example:
```yaml
FirstVolumeMounts: |
  - name: shared-data
    mountPath: /mnt/shared-data
    readOnly: false

VolumeMountsConfig: |
  - name: shared-data
    emptyDir: {}
```

the first parameter, will generate the same code inside of the containers and the second will enable it. If you need more volumeMounts you can use the extraVolumeMounts multiple times.


### CMF (ConfigMapsFiles)
Helm Charts don't allow the inclusion of files outside of the chart directory, for example:
```bash
.
├── LICENSE
├── monochart
│   ├── charts
│   ├── Chart.yaml
│   ├── LICENSE
│   ├── chart-config.json
│   ├── README.md
│   ├── templates
│   │   ├── _common_names.tpl
│   │   ├── configmapfile.yaml
│   │   ├── configmap.yaml
│   └── values.yaml
├── README.md
├── app
│   ├── config.xml
```

We can include/read the file **chart-config.json**, but not the file **config.xml** on app directory, because it is outside from the chart directory. To workaroung this, we have add a template in the monochart that will read the values from **"--set-file"** parameter from helm or the parameters **set:** from helmfile.

But, it need to have a specific format, like this:

```yaml
# helmfile
releases:
    - name: test
    [... cut ...]

    set:
      # This will load a local file inside of a configmap resource (ConfigMapFiles).
      # You need to follow this exact syntax:
      # - name: cmf.The_Name_of_the_Resource.data
      #   file: /path/relative/to/manifest
      # NOTE: Rememeber to add the cmf.name to "envFrom.configMaps" to have it inside of container.
      - name: cmf.The_Name_of_the_Resource.data
        file: /path/relative/to/manifest
      - name: cmf.pos-config-template.data
        file: files/pos-config-template.json

    values:
      envFrom:
        secrets:
          - The_Name_of_the_Resource
          - pos-config-template
```

These configuration will generate two CMF (ConfigMapsFiles) called **The_Name_of_the_Resource** and **pos-config-template** with the content of the **/path/relative/to/manifest** and **files/pos-config-template.json** respectively.

### Mount Config Map files on the pod

Config Map files can deliver configuration to stock Docker images without altering images itself. Use case may be to
configure Nginx or other web application that has to run in Spoton specific way but the image not necessairly has to be
maintained by Spoton.

Two approaches how to achieve this goal are presented below. From my limited experience it's impossible to mix them  in
a single Config Map. Using separate config maps can be a solution.

When reading examples below note the `mountPath` value to differentiate the way the files are mounted.

#### Separate directory

Mount a single or a bunch of files inside a given directory. The downside is that it will cover this directory if
exist. That means any files that are available in this directory in stock Docker image won't be accessible.

Helmfile snippet example (the volume with `index.html` file will be mounted in `/usr/share/nginx/html` directory):

```yaml
(...)
        configMaps:
          default:
            enabled: true
            mountPath: /usr/share/nginx/html
            files:
              "index.html": |-
                <!DOCTYPE html>
                <html lang="en">
                <head>
                </head>
                <body>
                  Hello world! <br/>
                </body>
                </html>
```

Live applications examples:

- [receipts-web](https://github.com/SpotOnInc/receipts-web/blob/6cbd7e73dfff376e037467bdf8c0059313e3cf54/deploy/releases/helm-action.yaml#L58-L99)
  configures stock NGINX docker image with Config Map config files.

#### Single config file

It's useful to mount a file to given directory without affecting files that are already exist in this directory. The
downside is that the directory has to exist.

Helmfile snippet example (the volume will be mounted as `/usr/share/nginx/html/index.html` file without affecting other
files in `/usr/share/nginx/html/` catalog):

```yaml
(...)
        configMaps:
          default:
            enabled: true
            mountPath: /usr/share/nginx/html/index.html
            files:
              "index.html": |-
                <!DOCTYPE html>
                <html lang="en">
                <head>
                </head>
                <body>
                  Hello world! <br/>
                </body>
                </html>
```

Live applications examples:

- [import-map](https://github.com/SpotOnInc/import-map/blob/429717a52b21e20da62b2f792fe447dbfbf02f69/deploy/releases/import-map-server.yaml#L50-L65)
  server delivers a single config file to a default config location populated with other files.

### EKS: Hide app URLs behind ZScaler (OIDC replacement for EKS using Application Load Balancer path-based routing)

We can make ingress address available from public Internet but sometimes we want to limit access just to Spoton
employees. In this case ZScaler integration comes handy. From the networking perspective we create ALB rule to allow
access to traffic that source originates from one of ZScaler IP addresses.

The general idea is that all the URL paths are behind ZScaler but we can expose some endpoints publicly.

#### How to start

Ingress annotation indicating we want to use Application Load Balancer are necessary

```yaml
(...)
        ingress:
          default:
            enabled: true
            className: alb
            annotations:
              # Ingresses with the same group will use the same Load Balancer rather than create new one
              alb.ingress.kubernetes.io/group.name: '{{ $AppName }}'
              alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
              alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
              # Target type "IP" is required for service type "ClusterIP"
              # If we want to change to ingress target type "instance" we have to use service type "NodePort"
              alb.ingress.kubernetes.io/target-type: ip
              # Application Load Balancer has to be publicly available to endpoint be reachable externally.
              alb.ingress.kubernetes.io/scheme: internet-facing
              # Health check path has to be adjusted according to your application so load balancer can check if it can
              # route traffic to your service.
              alb.ingress.kubernetes.io/healthcheck-path: /
```

Then, we have to update `hosts` section. There are 2 notations supported.

1. Legacy. Backward compatibility with Network Load Balancer.

   This mode helps to migrate from `nginx` ingress class to `alb`, however, it's not secure at all as the ZScaler
   configuration is skipped and entire endpoint is exposed to public internet. `hosts` ingress section doesn't require
   any modifications and can be left as it is. Just add annotations mentioned above and you're good to go.

   ```yaml
            hosts:
              # APP_HOST is calculated and provided from CI/CD
              # It represents the hostname to route for, and the `/` the path to forward requests to
              '{{ env "APP_HOST" }}': /
              # Allows us to optionally define extra DNS names to send to this ingress
              {{- if index .Values "vanityDomain" }}
              '{{ .Values.vanityDomain }}': /
              {{- end }}
   ```

    Live apps examples:

    - [olo-web-api](https://github.com/SpotOnInc/giftcard-service/blob/36addd4fa2d6ad6fa2105089433d7c8e2ec1da7c/deploy/releases/giftcard-api.yaml#L121-L128)
    - [dishout-service](https://github.com/SpotOnInc/dishout-service/blob/22547a1da6c1054ec282c192aff630bf84666385/deploy/releases/dishout-service.yaml#L291)
    - [giftcard service](https://github.com/SpotOnInc/giftcard-service/blob/36addd4fa2d6ad6fa2105089433d7c8e2ec1da7c/deploy/releases/giftcard-api.yaml#L121-L128)

1. Hide everyting behind ZScaler but expose some endpoints.

   This is a preferred way of keeping URLs private because it restricts access by default without extra configuration.
   The hosts section should look like below:

   ```yaml
            hosts:
              '{{ env "APP_HOST" }}':
              {{- if index .Values "public_paths" }}
                {{- range .Values.public_paths }}
                - '{{ . }}'
                {{- end }}
              {{- end }}

              # Allows us to optionally define extra DNS names to send to this ingress.
              # The $root variable is important because the nested range loop has to refer to top-level .Values
              {{- $root := . -}}
            {{- if index .Values "vanityDomains" }}
              {{ range $domain := .Values.vanityDomains }}
              '{{ $domain }}':
                {{- if index $root.Values "public_paths" }}
                  {{- range $path := $root.Values.public_paths }}
                - '{{ $path }}'
                  {{- end }}
                {{- end }}
              {{- end }}
            {{- end }}
    ```

    By default the app URL will be accessible via ZScaler only. Note the vanity domains will also be affected. If you'd
    like to expose some URL paths add `public_paths` list to the top of helmfile. Example below shows the `/status` exact
    path and `/api/` prefix path on staging will be accessible to anyone on public internet:

    ```yaml
    environments:
      staging:
        values:
          - public_paths:
            - /status
            - /api/*
    ```

    Live apps examples:

    - [payments-pci-data-collection-service](https://github.com/SpotOnInc/payments-pci-data-collection-service/blob/9f8880f275bdc053f18b629357e9d61dcc86f557/deploy/releases/payments-pci-data-collection-service.yaml#L38-L39)
      uses list of `public_paths` to expose a production endpoint to public Internet. It's necessary for customer's
      browser to reach to this endpoint.

#### Use non-default ZScaler proxy IP addresses

By default ZScaler Proxy IP addresses work for most environments. However, if that require customization an example
below explains how it can be achieved in helmfile.

1. Create `zscalerProxyIPs` variable in your helmfile.

  ```yaml
  environments:
    pci-unlimited:
      values:
        - zscalerProxyIPs:
          - 54.82.104.143/32
          - 54.86.79.65/32
  ```

1. Loop through values of this variable in `ingress` declaration

  ```yaml
    ingress:
      default:
        enabled: true
        zscalerProxyIPs:
        {{ range .Values.zscalerProxyIPs }}
          - {{ . }}
        {{ end }}
  ```

### RBAC (Role based access control)

Role is a way to provide permission to Service Account to manipulate Kubernetes resources. For example we can let our
pod to create/delete deployment on our behalf (as a part of CI/CD process) or schedule to delete development pods for
the weekend.

You can deploy Kubernetes Roles/ClusterRoles and Role bindings/Cluster role bindings with monochart. There are 3 use
cases that are covered:

1. Deploy service account with role permissions.
1. Attach role to existing service account.
1. Deploy role and role binding to another namespace and attach it to existing service account.

#### 1. Deploy service account with role permissions

In this scenario monochart will create service account with role attached to it via role binding.

```yaml
serviceAccount:
  create: true  

rbacRole:
  create: true
  clusterWide: false # whether to create Role/RoleBinding or ClusterRole/ClusterRoleBinding
  namespace: ""
  rules: |
    - apiGroups:
      - apps
      resources:
      - deployments
      verbs:
      - get
      - list
```

#### 2. Attach role to existing service account

Monochart won't create a new service account but it will just create role and role binding. It's useful if the service
account is managed in another helm release and we want to provide additional permissions without altering existing
release.

Note the `serviceAccount.create` is `false` and the `serviceAccount.name` parameter is populated.

```yaml
serviceAccount:
  create: false
  name: existing-service-account

rbacRole:
  create: true
  clusterWide: false
  namespace: ""
  rules: |
    - apiGroups:
      - apps
      resources:
      - deployments
      verbs:
      - get
      - list
```

#### 3. Deploy role and role binding to another namespace

We want to give a service account permission to access/alter Kubernetes resources in another namespace. Example: we want
our CI/CD worker pod to create a deployment in another namespace.

Note the `serviceAccount.create` is `false`, the `serviceAccount.name` and `serviceAccount.namespace` parameters are
provided.

```yaml
serviceAccount:
  create: false
  name: existing-service-account

rbacRole:
  create: true
  clusterWide: false
  namespace: "existing-namespace"
  rules: |
    - apiGroups:
      - apps
      resources:
      - deployments
      verbs:
      - get
      - list
```

## TODO

### Helm git plugin

Helm/helmfile have a plugin that allow use a git repository as a helm chart repository directly.
This works very easy when you have a public git repository, but in our case, our [helmchart](https://github.com/SpotOnInc/helmcharts/) repository is private and that have generate some problem to access it from CD.

To workaround it, we have followed the idea from @JB to make a clone from the helmchart repository inside of the CD and use this local directory as chart. For example:

```yaml
# helmfile with public git chart repository.
repositories:
  # Spoton helmcharts repository
  - name: spoton-git
    url: "git+ssh://git@github.com/

releases:
  - name: test
    # the chart this release uses
    chart: "spoton-git/spoton-monochart
    version: 1.1.1
```

the workaround one time that we have the repository cloned

```yaml
# helmfile with public git chart repository.
# repositories:
#   # Spoton helmcharts repository
#   - name: spoton-git
#     url: "git+ssh://git@github.com/

releases:
  - name: test
    # the chart this release uses
    chart: "/codefresh/volume/helmcharts/monochart"
    version : 1.1.1
```

This work good for now, **but maybe in the future** we will have performance problem if the repository grow up in size.

### Include DataDog enviroment by default.
### Include networkpolices on templates.
