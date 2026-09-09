provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy = "platform/aws"
    }
  }
}
