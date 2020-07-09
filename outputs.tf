output "public_key" {
  value = "${tls_private_key.appkey.public_key_openssh}"
}

# output "private_key" {
#   value = "${tls_private_key.appkey.private_key_pem}"
# }
