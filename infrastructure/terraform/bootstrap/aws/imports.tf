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
  to = aws_iam_service_linked_role.spot
  id = "arn:aws:iam::183590992229:role/aws-service-role/spot.amazonaws.com/AWSServiceRoleForEC2Spot"
}

# The six inline role policies imported here in July 2026 became
# customer-managed policies on 2026-11-01; their import blocks were removed so
# the next apply deletes the inline versions and creates the managed ones.
