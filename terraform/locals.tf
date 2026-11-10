# Values fixed by the approved POC design. Not inputs on purpose: a change
# here is a code review, which is the configuration standard PCI DSS
# 1.3.1.a / 1.3.2.a asks to examine.
locals {
  name     = "cde"
  vpc_cidr = "10.0.0.0/16"

  # PCI DSS 1.3.2: the only domains the app may reach, over HTTPS.
  allowed_egress_domains = ["secureweb.com", "example.com"]

  app_port          = 8080
  app_instance_type = "t3.micro"
  db_instance_type  = "t3.micro"
}
