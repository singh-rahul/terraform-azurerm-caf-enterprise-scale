#
# The client-id, client-secret and tenant-id are stored into the keyvault to support password rotation
#
# If the following struture is set in the config section of the keyvault, the secret can be stored in a keyvault generated by a different landing zone

#   keyvaults  = {
#     secrets = {
#       remote_tfstate = {
#         tfstate_key = "foundations" (define the state your calling landing zone has permission to read)
#         lz_key      = "launchpad"
#         output_key  = "keyvaults"
#       }
#       secret_prefix         = "aadapp-caf-launchpad-github-terraformdev-github-integration-landingzones"
#     }
#   }
#

data "terraform_remote_state" "keyvaults" {
  for_each = {
    for key, value in try(var.settings.keyvaults, {}) : key => value
    if try(value.remote_tfstate, null) != null
  }

  backend = "azurerm"
  config = {
    storage_account_name = var.tfstates[each.value.remote_tfstate.tfstate_key].storage_account_name
    container_name       = var.tfstates[each.value.remote_tfstate.tfstate_key].container_name
    resource_group_name  = var.tfstates[each.value.remote_tfstate.tfstate_key].resource_group_name
    key                  = var.tfstates[each.value.remote_tfstate.tfstate_key].key
    use_msi              = var.use_msi
    subscription_id      = var.use_msi ? var.tfstates[each.value.remote_tfstate.tfstate_key].subscription_id : null
    tenant_id            = var.use_msi ? var.tfstates[each.value.remote_tfstate.tfstate_key].tenant_id : null
  }
}


resource "azurerm_key_vault_secret" "client_id" {
  for_each = try(var.settings.keyvaults, {})

  name         = format("%s-client-id", each.value.secret_prefix)
  value        = azuread_application.app.application_id
  key_vault_id = try(data.terraform_remote_state.keyvaults[each.key].outputs[each.value.remote_tfstate.output_key][each.value.remote_tfstate.lz_key][each.key].id, var.keyvaults[each.key].id)

  lifecycle {
    ignore_changes = [
      value
    ]
  }

}

resource "azurerm_key_vault_secret" "client_secret" {
  for_each        = try(var.settings.keyvaults, {})
  name            = format("%s-client-secret", each.value.secret_prefix)
  value           = azuread_service_principal_password.app.value
  key_vault_id    = try(data.terraform_remote_state.keyvaults[each.key].outputs[each.value.remote_tfstate.output_key][each.value.remote_tfstate.lz_key][each.key].id, var.keyvaults[each.key].id)
  expiration_date = timeadd(timestamp(), format("%sh", try(var.settings.password_expire_in_days, 180) * 24))

  lifecycle {
    ignore_changes = [
      expiration_date, value
    ]
  }
}

resource "azurerm_key_vault_secret" "tenant_id" {
  for_each     = try(var.settings.keyvaults, {})
  name         = format("%s-tenant-id", each.value.secret_prefix)
  value        = var.client_config.tenant_id
  key_vault_id = try(data.terraform_remote_state.keyvaults[each.key].outputs[each.value.remote_tfstate.output_key][each.value.remote_tfstate.lz_key][each.key].id, var.keyvaults[each.key].id)
}
