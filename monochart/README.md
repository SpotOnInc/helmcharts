# Monochart

## Introduction
We have to made a fork from https://github.com/cloudposse/charts/tree/master/incubator/monochart, because the CP chart is a bit outdate and don't include all the parameters that we need, like sealedsecrets, initconatiners and networkpolices.

## Changes

### common.labels
We have changed the common.labes from:

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
```

The first will create a **sealed secret** resource called google-secrets with two secrets (SECRET_NAME and ANOTHER_SECRET)... when deployed, kubernetes will use the private key to decipher this secrets and get the correct value.

The second, will setup this secret inside of the containers.

> Note: To generate you can use [kubeseal](https://github.com/bitnami-labs/sealed-secrets#installation-from-source) from CLI or you can use the Spoton [WebSeal](https://webseal.qa.spoton.sh/) interface.


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

We will can include/read the file **chart-config.json**, but not the file **config.xml** on app directory, because it is outside from the chart directory. To workaroung this, we have add a template in the monochart that will read the values from **"--set-file"** parameter from helm or the parameters **set:** from helmfile. 

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


## TODO:

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
