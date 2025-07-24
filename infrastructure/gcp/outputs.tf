output "function_name" {
  description = "The name of the function"
  value       = google_cloudfunctions2_function.function.name
}

output "function_endpoint" {
  description = "The API endpoint URL address"
  value       = google_cloudfunctions2_function.function.service_config[0].uri
}

output "service_account_email" {
  description = "The email of the service account"
  value       = google_service_account.service_account.email
}
