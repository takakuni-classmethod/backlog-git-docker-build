######################################
# KeyPair Configuration
######################################
resource "tls_private_key" "backlog" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "public_key_openssh" {
  filename        = "${path.module}/keypair/${local.prefix}.pub"
  content         = tls_private_key.backlog.public_key_openssh
  file_permission = "0600"
}