# Terraform Mastery, Lesson 1: Your First Real AWS Environment

Welcome, student. We'll build the environment first, then go through the workflow. Before the code, here are the four ideas everything rests on:

| Concept | What it means |
|---|---|
| **Declarative** | You describe the *desired end state*. Terraform works out the steps. |
| **State** | `terraform.tfstate` is Terraform's memory of what it has built. Never edit it by hand. |
| **Dependency graph** | When one resource references another (`aws_instance.web` → `aws_key_pair.this.key_name`), Terraform builds them in the right order automatically. |
| **Providers** | Plugins that talk to APIs (AWS, TLS, random, and so on). |

---

## Step 0: Pre-flight check

```bash
terraform version          # confirm your install
aws sts get-caller-identity   # confirm which AWS account/user Terraform will act as
```

If the second command fails, fix your credentials before going further.

## Step 1: Project layout

```bash
mkdir terraform-aws-lab && cd terraform-aws-lab
touch providers.tf variables.tf main.tf outputs.tf .gitignore
```

```
terraform-aws-lab/
├── providers.tf   # Terraform settings + provider config
├── variables.tf   # Inputs
├── main.tf        # Resources and data sources
├── outputs.tf     # Values printed after apply
└── .gitignore
```

Terraform reads every `.tf` file in the directory as one configuration, so the split is purely for humans.

---

## Step 2: `providers.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Every taggable resource gets these automatically
  default_tags {
    tags = local.common_tags
  }
}
```

**Lesson:**
- `required_version` and `version = "~> 6.0"` pin versions. `~> 6.0` means "any 6.x, but not 7.0". Pinning keeps your builds reproducible.
- We use four providers: `aws` for infrastructure, `tls` to generate the key, `local` to save it to disk, and `random` for the unique bucket suffix.
- `default_tags` is a best practice. You write the tags once and they apply everywhere.

---

## Step 3: `variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names"
  type        = string
  default     = "tflab"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
    error_message = "project_name must be 3-20 characters: lowercase letters, numbers, hyphens only (S3 naming rules)."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH in. Set this to YOUR_IP/32."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "allowed_ssh_cidr must be a valid CIDR block, e.g. 203.0.113.10/32."
  }
}
```

**Lesson:**
- Every variable gets a `type`, a `description`, and usually a `default`. Variables without defaults make Terraform prompt you.
- `validation` blocks catch bad input at `plan` time, before anything is created.
- `0.0.0.0/0` means the whole internet. I left it as the default so the lab works out of the box, but you should override it with your own IP (shown in Step 7).

---

## Step 4: `main.tf`

```hcl
############################
# Locals (computed values)
############################
locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

############################
# Data sources (READ existing things)
############################

# Latest Amazon Linux 2023 AMI, never hardcoded
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Use the account's default VPC to keep this lab simple
data "aws_vpc" "default" {
  default = true
}

############################
# S3 bucket (globally unique name)
############################
resource "random_id" "bucket_suffix" {
  byte_length = 4 # 8 hex characters
}

resource "aws_s3_bucket" "app" {
  bucket        = "${local.name_prefix}-data-${random_id.bucket_suffix.hex}"
  force_destroy = true # lab only: lets `destroy` delete a non-empty bucket
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket = aws_s3_bucket.app.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id

  versioning_configuration {
    status = "Enabled"
  }
}

############################
# SSH key pair (auto-generated)
############################
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  key_name   = "${local.name_prefix}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = "${path.module}/${local.name_prefix}-key.pem"
  file_permission = "0400"
}

############################
# Security group (SSH only)
############################
resource "aws_security_group" "ssh" {
  name        = "${local.name_prefix}-ssh-sg"
  description = "Allow SSH inbound"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name = "${local.name_prefix}-ssh-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ssh.id
  description       = "SSH from allowed CIDR"
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ssh.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

############################
# IAM: role + policy + instance profile
############################
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]
  }

  statement {
    sid       = "ObjectAccess"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.app.arn}/*"]
  }
}

resource "aws_iam_role_policy" "s3_access" {
  name   = "${local.name_prefix}-s3-access"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_access.json
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

############################
# EC2 instance
############################
resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.ssh.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  associate_public_ip_address = true

  # Require IMDSv2 (security best practice)
  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    echo "export APP_BUCKET=${aws_s3_bucket.app.bucket}" >> /etc/profile.d/app.sh
  EOF

  user_data_replace_on_change = true

  tags = {
    Name = "${local.name_prefix}-web"
  }
}
```

**Lesson: what to notice in this file**

1. **Data vs. resource.** `data` blocks *read* things that already exist (the AMI, the VPC). `resource` blocks *create and manage* things.
2. **Implicit dependencies.** `aws_instance.web` references `aws_key_pair.this.key_name`, so Terraform knows to build the key pair first. You rarely need `depends_on`.
3. **Interpolation.** `"${local.name_prefix}-key"` embeds values into strings. Resource attributes (`aws_s3_bucket.app.arn`) and `locals` keep everything DRY. Rename the project once and every resource follows.
4. **Why `random_id`.** S3 bucket names are global across all AWS accounts. A random suffix, stored in state, keeps the name unique and stable across runs.
5. **Least privilege.** The IAM policy grants access to *only this one bucket*, not `s3:*` on `*`.
6. **Security note.** The generated private key lives in your Terraform state file. That's fine for learning, but in production you'd create keys outside Terraform or use SSM Session Manager and skip SSH entirely.

---

## Step 5: `outputs.tf`

```hcl
output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.web.id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.web.public_ip
}

output "ami_id_used" {
  description = "The AMI Terraform resolved dynamically"
  value       = data.aws_ami.al2023.id
}

output "s3_bucket_name" {
  description = "Generated S3 bucket name"
  value       = aws_s3_bucket.app.bucket
}

output "private_key_path" {
  description = "Path to the generated private key"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_command" {
  description = "Command to connect to the instance"
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ec2-user@${aws_instance.web.public_ip}"
}
```

## Step 6: `.gitignore`

```gitignore
.terraform/
*.tfstate
*.tfstate.*
*.pem
*.tfvars
crash.log
```

`.terraform.lock.hcl` **should** be committed. State files and keys never should be.

## Step 7: Lock SSH to your IP (recommended)

Create `terraform.tfvars`:

```hcl
allowed_ssh_cidr = "YOUR.PUBLIC.IP.HERE/32"
```

Find your IP with `curl -s https://checkip.amazonaws.com`. Terraform automatically loads `terraform.tfvars`.

---

## Step 8: The Terraform lifecycle, applied to this project

Run these in order from inside the project folder.

### 1. `terraform init`
Downloads the four providers into `.terraform/` and creates `.terraform.lock.hcl`, which pins exact provider versions and checksums. **Run it first, and again whenever you add a provider or module.**

### 2. `terraform fmt`
Rewrites your files to canonical style. Use `terraform fmt -recursive` for subfolders, and `terraform fmt -check` in CI pipelines. **Make this a habit before every commit.**

### 3. `terraform validate`
Checks syntax and internal consistency (bad references, wrong attribute names, invalid types). It works **offline** and doesn't touch AWS. It's the fastest way to catch typos.

### 4. `terraform plan -out=tfplan`
Compares your code, the state, and real AWS, then shows what *would* change:
- `+` create, `~` update in place, `-` destroy, `-/+` replace

**Read the plan carefully every time.** For this project, expect roughly **17 resources to add**. Saving it with `-out=tfplan` guarantees that what you review is exactly what gets applied.

### 5. `terraform apply tfplan`
Executes the saved plan. Without a saved plan, `terraform apply` generates a fresh one and asks you to type `yes`. When it finishes, your outputs are printed.

### 6. Verify it worked

```bash
terraform output                    # view all outputs
terraform output -raw ssh_command   # copy-paste friendly

# Connect (run the command from the output), then on the instance:
aws s3 ls s3://$APP_BUCKET                       # should work (empty bucket)
echo "hello terraform" > test.txt
aws s3 cp test.txt s3://$APP_BUCKET/             # should work
aws s3 ls s3://some-other-bucket                 # should be DENIED: least privilege in action
```

(Log out and back in first if `$APP_BUCKET` isn't set, since the profile script loads on login. The instance gets its credentials from the instance profile, so you never put keys on the box.)

### 7. `terraform destroy`
Tears down everything in the state, in reverse dependency order. Use `terraform plan -destroy` first to preview. **Always destroy lab resources when you're done** to avoid charges.

### Useful companions

```bash
terraform state list              # what Terraform is tracking
terraform show                    # human-readable state
terraform graph | dot -Tpng > graph.png   # visualize dependencies (needs Graphviz)
terraform apply -var="instance_type=t3.small"   # override a variable on the CLI
```

---

## Experiments to cement the learning

Do these in order, and **predict the plan output before you run it**:

1. **Change in place.** Add a new tag in `common_tags` and run `plan`. Which resources show `~`?
2. **Forced replacement.** Change `instance_type` to `t3.small`. Does it replace the instance or modify it? Why? (Stop-start type changes can be in-place, so read the plan carefully.)
3. **Drift.** In the AWS console, manually add a tag to the security group, then run `terraform plan`. Terraform detects the difference. This is what *state reconciliation* means.
4. **Validation.** Run `terraform plan -var="environment=test"` and read the error.
5. **Break it on purpose.** Misspell `aws_s3_bucket.app.arn` in the IAM policy and run `terraform validate`.

---

## Your learning roadmap after this lab

1. **Variables deep dive:** `tfvars` files per environment, `sensitive = true`, complex types (`map`, `object`)
2. **Meta-arguments:** `count`, `for_each`, `depends_on`, `lifecycle` (`prevent_destroy`, `create_before_destroy`)
3. **Remote state:** S3 backend with native locking (`use_lockfile = true`), which is essential for teams
4. **Modules:** refactor this lab into a reusable `ec2-with-s3` module
5. **Networking:** build your own VPC, public/private subnets, and NAT instead of the default VPC
6. **Testing and quality:** `terraform test`, `tflint`, `checkov` or `trivy` for security scanning
7. **CI/CD:** GitHub Actions running `fmt -check`, `validate`, and `plan` on pull requests
8. **Certification:** HashiCorp Terraform Associate, which this roadmap maps onto well

---

**Your homework:** build this, run the five experiments, and paste me any errors or surprising plan output. Tell me *what you expected* vs. *what happened*. That's where the real learning happens. When you're ready, we'll move on to `for_each`, remote state, or turning this into a module. Which one do you want next?
