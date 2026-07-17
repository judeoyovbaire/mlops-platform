# One-time import of the live bootstrap resources - the original local
# state was lost (July 2026). Safe to keep: import blocks are no-ops once
# the resources are in state.
import {
  to = aws_kms_key.terraform_state
  id = "192f3a5a-dbf6-4c1d-a473-1d17d2a8c0d8"
}
import {
  to = aws_kms_alias.terraform_state
  id = "alias/mlops-platform-terraform-state"
}
import {
  to = aws_s3_bucket.terraform_state
  id = "mlops-platform-tfstate-183590992229"
}
import {
  to = aws_s3_bucket_versioning.terraform_state
  id = "mlops-platform-tfstate-183590992229"
}
import {
  to = aws_s3_bucket_server_side_encryption_configuration.terraform_state
  id = "mlops-platform-tfstate-183590992229"
}
import {
  to = aws_s3_bucket_public_access_block.terraform_state
  id = "mlops-platform-tfstate-183590992229"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.terraform_state
  id = "mlops-platform-tfstate-183590992229"
}
import {
  to = aws_dynamodb_table.terraform_locks
  id = "mlops-platform-terraform-locks"
}
import {
  to = aws_iam_openid_connect_provider.github
  id = "arn:aws:iam::183590992229:oidc-provider/token.actions.githubusercontent.com"
}
import {
  to = aws_iam_role.github_actions
  id = "mlops-platform-github-actions"
}
import {
  to = aws_iam_role_policy.terraform_state_access
  id = "mlops-platform-github-actions:terraform-state-access"
}
import {
  to = aws_iam_role_policy.terraform_eks_ec2
  id = "mlops-platform-github-actions:terraform-eks-ec2"
}
import {
  to = aws_iam_role_policy.terraform_iam
  id = "mlops-platform-github-actions:terraform-iam"
}
import {
  to = aws_iam_role_policy.terraform_storage
  id = "mlops-platform-github-actions:terraform-storage"
}
import {
  to = aws_iam_role_policy.secretsmanager_rds_managed
  id = "mlops-platform-github-actions:secretsmanager-rds-managed"
}
import {
  to = aws_iam_role_policy.terraform_services
  id = "mlops-platform-github-actions:terraform-services"
}
import {
  to = aws_iam_service_linked_role.spot
  id = "arn:aws:iam::183590992229:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
}
