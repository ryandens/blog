# Ryan's blog
In this repository, I use [Hugo](https://gohugo.io/) to build the static content for my blog. In addition, it has the Terraform responsible for provisioning the S3 Bucket, Route53 record, SSL certificate, and CloudFront distribution responsible for serving the static content on [ryandens.com](https://www.ryandens.com).

## 👷 Local development setup

First, follow the [Hugo install instructions](https://gohugo.io/getting-started/installing/). I downloaded their latest Debian package and installed using the command

```bash
$ dpkg -i /path/to/hugo_0.XX.0_Linux-64bit.deb
```

To run an HTTP server locally serving the generated static content, simply run
```bash
$ hugo server
```

To serve the content including draft blog posts, simply append `-D` to also publish drafts

```bash
$ hugo server -D
```


## 🚀 Deploying infrastructure
First, install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) and [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html).
Make sure you've configured your environment to pickup your AWS credentials.

Next, deploy the infrastructure. Note that the first time you deploy the infrastructure, you will have to tell the domain registry which DNS servers to route to. These will be outputted as a result of applying the terraform code. In addition, you will have to confirm via email that you own the domain name you claim so the SSL certificate can be signed by Amazon.

```bash
$ cd prod && terraform apply
```

When prompted accept the terraform plan to deploy to production.

## 🚀 Deploying new content
To update content in the S3 bucket, we use hugo's built in functionality. Syncing content with an S3 bucket is dead simple with the AWS CLI, but Hugo makes invalidating the CloudFront cache for the changed files trivial. 

```bash
$ cd site && hugo && hugo deploy --maxDeletes -1 --invalidateCDN
```
