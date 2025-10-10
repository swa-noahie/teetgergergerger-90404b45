resource "aws_dynamodb_table" "main" {
  name         = "luv-teetgergergerger-9de1c5a8-main"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    enabled        = true
    attribute_name = "expire_at"
  }

  tags = {
    ProjectId = "9de1c5a8-7bbb-4f64-b57e-a1ae3963ec20"
    Project   = "teetgergergerger"
    Mode      = "demo_fast"
  }
}