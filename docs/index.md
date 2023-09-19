# Docs for helmcharts

Helm chart repository for Spoton projects. A home of Monochart that we're using to deploy every Spoton project.


## Working locally with these docs
**Warning**: the following examples make use of the [github-cli](https://cli.github.com/)

1. checkout and build the `github-action-publish-docs` container
```
gh repo clone spotoninc/github-action-publish-docs
cd github-action-publish-docs
docker build . -t spoton-techdocs:latest
```

2. run the `techdocs-cli` using this image:

```
npm install -g @techdocs/cli
cd helmcharts
techdocs-cli serve --docker-image spoton-techdocs --verbose --docker-entrypoint "mkdocs"
```