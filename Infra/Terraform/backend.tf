terraform {
  backend "s3" {
    bucket = var.bucket
        key    = "voting-app/terraform.tfstate"
        region = "us-east-1"
        encrypt = true
  }
}