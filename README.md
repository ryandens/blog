# Ryan's blog
I use [Hugo](https://gohugo.io/) to build the static content for my blog. In addition, it hosts the Terraform responsible for provisioning the S3 Bucket, Route53 record, SSL certificate, and CloudFront distribution responsible for serving the static content on [ryandens.com](https://ryandens.com). Simple scripts located in [ci/](./ci/) are responsible for uploading new content to the S3 bucket and invalidating cached files on CloudFront. 

## Local development setup

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


## Deploying 
First, install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) and [Terraform](https://learn.hashicorp.com/terraform/getting-started/install.html).
Make sure you've configured your environment to pickup your AWS credentials. 

Next, generate the static content for the site.

```bash
$ cd site && hugo
```

This will generate the new and/or updated static content for the site. 

Next, deploy the infrastructure. Note that the first time you deploy the infrastructure, you will have to tell the domain registry which DNS servers to route to. These will be outputted as a result of applying the terraform code. In addition, you will have to confirm via email that you own the domain name you claim so the SSL certificate can be signed by Amazon.

```bash
$ cd prod && terraform apply
```

When prompted accept the terraform plan to deploy to production.
