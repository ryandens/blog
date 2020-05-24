output "name_servers" {
  description = "the Route 53 Zone for configuring your domain name provider"
  value       = module.my-static-site.name_servers
}