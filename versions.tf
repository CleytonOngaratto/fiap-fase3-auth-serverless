terraform {
  # >= 1.11: lock nativo do S3 (`use_lockfile`), que dispensa DynamoDB.
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Empacota a Lambda: o módulo terraform-aws-modules/lambda/aws exigiria Python, ausente aqui.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Config parcial: o bucket depende da conta do lab.
  backend "s3" {}
}
