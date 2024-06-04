provider "aws" {
  region = "eu-central-1" 
}

resource "aws_s3_bucket" "lambda_bucket" {
  bucket = "art-sign-test2"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.lambda_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_signer_signing_profile" "example_signing_profile" {
  name        = "artem3_signing_profile"
  platform_id = "AWSLambda-SHA384-ECDSA"

  signature_validity_period {
    type  = "MONTHS"
    value = 12
  }

  tags = {
    Environment = "Production"
    Project     = "MyLambdaProject"
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.lambda_bucket.bucket
  key    = "my_lambda_function.zip"
  source = "my_lambda_function.zip"
  etag   = filemd5("my_lambda_function.zip")
}


resource "aws_signer_signing_job" "signing_job" {
  profile_name = aws_signer_signing_profile.example_signing_profile.name

  source {
    s3 {
      bucket = aws_s3_object.lambda_zip.bucket
      key    = aws_s3_object.lambda_zip.key
      version = aws_s3_object.lambda_zip.version_id
    }
  }

  destination {
    s3 {
      bucket = aws_s3_bucket.lambda_bucket.bucket
      prefix = "signed/"
    }
  }
}

#data "aws_s3_object" "signed_lambda_zip" {
#  bucket = aws_s3_bucket.lambda_bucket.bucket
#  key    = "signed/my_lambda_function.zip"

#  depends_on = [aws_signer_signing_job.signing_job]
#}

resource "aws_lambda_code_signing_config" "new_csc" {
  allowed_publishers {
    signing_profile_version_arns = [
      aws_signer_signing_profile.example_signing_profile.arn,
    ]
  }

  policies {
    untrusted_artifact_on_deployment = "Warn"
  }

  description = "My awesome code signing config."
}
#bucket = aws_signer_signing_job.this.signed_object[0].s3[0].bucket
#    key    = aws_signer_signing_job.this.signed_object[0].s3[0].key

resource "aws_lambda_function" "my_lambda_function" {
  function_name = "my_lambda_function"
  s3_bucket     = aws_s3_bucket.lambda_bucket.bucket
  s3_key        = aws_signer_signing_job.signing_job.signed_object[0].s3[0].key
  handler       = "my_lambda_function.handler"
  runtime       = "python3.12"
  role          = aws_iam_role.lambda_exec_role.arn
  code_signing_config_arn = aws_lambda_code_signing_config.new_csc.arn #aws_signer_signing_profile.example_signing_profile.arn #new_csc.arn #"arn:aws:lambda:eu-central-1:344226711005:code-signing-config:csc-09d1a2fa0b3279058" 
  
  
  depends_on = [aws_signer_signing_job.signing_job]
}
