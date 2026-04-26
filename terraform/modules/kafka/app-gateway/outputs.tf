output "public_ip_address" {
  description = "Public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw_pip.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the Application Gateway public IP."
  value       = azurerm_public_ip.appgw_pip.fqdn
}

output "gateway_id" {
  description = "Resource ID of the Application Gateway."
  value       = azurerm_application_gateway.this.id
}
