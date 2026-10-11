# Lesson 5: Data Sources (`data` blocks)

> **A `resource` block says "create this and manage it." A `data` block says "go look this up, I only want to read it."**

In the programming analogy, a `resource` is a **write** (like `INSERT`) and a `data` block is a **read** (like `SELECT`). Terraform will never create, change, or delete anything because of a data block.

---

## 1. Why we need data sources

Real infrastructure is never built from scratch in a vacuum. Your code has to connect to things that **already exist** or that **change over time**:

- A VPC the networking team built last year
- The latest AMI, which AWS publishes new versions of every few weeks
- The AWS account ID you're currently running in
- A secret stored in Secrets Manager
- A resource created by *another* Terraform project

Without data sources you'd **hardcode** IDs like `ami-0abc123...` or `vpc-0f9e...`. Those break when you switch regions or accounts, and they go stale when AMIs are retired.

| Hardcoded | Data source |
|---|---|
| `ami = "ami-0abc123def"` | Looks up the latest AMI at plan time |
| Breaks in another region | Works in any region |
| Silently goes out of date | Always current |
| Reviewer can't tell what it is | Self-documenting filters |

---

## 2. Anatomy of a data block

```hcl
data "aws_vpc" "default" {
  default = true
}
```

```
data  "aws_vpc"  "default"  { ...arguments... }
 │       │          │
 │       │          └─ local name you choose (used in references)
 │       └─ data source TYPE (provider defines what exists)
 └─ keyword
```

You reference it with a **`data.` prefix**:

```hcl
data.aws_vpc.default.id
```

Compare with a resource: `aws_s3_bucket.app.id`. If you forget the `data.` prefix, Terraform looks for a *resource* of that type and errors. This is the most common beginner mistake.

---

## 3. Your two data sources, explained

### The AMI lookup

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  ...
}
```

Think of this as a database query:

```sql
SELECT id FROM amis
WHERE owner = 'amazon'
  AND name LIKE 'al2023-ami-2023.%-x86_64'
  AND virtualization = 'hvm'
ORDER BY creation_date DESC
LIMIT 1
```

- `owners = ["amazon"]` is a **security best practice**. Without it, anyone can publish an AMI with a matching name, and you could launch a malicious image.
- `most_recent = true` picks the newest match.
- The result is used as `data.aws_ami.al2023.id` in the EC2 instance.

### The VPC lookup

```hcl
data "aws_vpc" "default" {
  default = true
}
```

Every AWS account has a default VPC per region. This finds it, and we use its ID for the security group.

---

## 4. When does a data source run?

Terraform reads data sources during **`plan`** (and refresh), so they're resolved **before** any resource is created, as long as their arguments are already known.

```
terraform plan
   │
   ├─ read data.aws_ami.al2023      ← queries AWS now
   ├─ read data.aws_vpc.default     ← queries AWS now
   └─ compute what to create using those results
```

One subtlety: if a data source depends on a value that **isn't known until apply** (for example, it filters on the ID of a resource that doesn't exist yet), Terraform defers the read until apply. That's normal.

**A consequence worth knowing:** because the AMI lookup runs each time, a newer Amazon Linux release can change `data.aws_ami.al2023.id` between runs. Your `aws_instance` would then show **replacement** in the plan. In production, this is why teams either accept it deliberately, pin the AMI, or add `lifecycle { ignore_changes = [ami] }` to the instance. Both choices are valid, so treat it as a conscious decision.

---

## 5. Five production use cases

**1. Current account and region info**
```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# e.g. globally unique bucket name without randomness
bucket = "${local.name_prefix}-${local.account_id}-logs"
```

**2. Availability zones**
```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

# use the first 3 AZs for subnets, in any region
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}
```
This is why the same code works in `us-east-1` and `ap-south-1` without edits.

**3. Reading an existing, shared VPC and subnets (very common in companies)**
```hcl
data "aws_vpc" "shared" {
  tags = {
    Name = "company-shared-vpc"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  tags = {
    Tier = "private"
  }
}
```
The network team owns the VPC. Your app team's Terraform *reads* it and builds inside it, without ever being able to break it.

**4. Building IAM policies in HCL (you already use this one)**
```hcl
data "aws_iam_policy_document" "s3_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]
  }
}
```
This one is special: it doesn't query AWS at all. It's a **pure-computation data source** that generates JSON, which is cleaner and safer than hand-writing JSON strings.

**5. Reading another Terraform project's outputs**
```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-state-bucket"
    key    = "network/terraform.tfstate"
    region = "us-east-1"
  }
}

# use: data.terraform_remote_state.network.outputs.vpc_id
```
This is how separate teams or stacks share information. We'll cover it properly in the remote state lesson.

---

## 6. Data source vs resource vs variable vs local

| | Reads from | Creates things? | Example |
|---|---|---|---|
| `variable` | The user | No | `var.instance_type` |
| `local` | Other values in your code | No | `local.name_prefix` |
| `data` | **The outside world** (AWS API, etc.) | **No** | `data.aws_ami.al2023.id` |
| `resource` | Your code | **Yes** | `aws_instance.web` |

---

## 7. Common mistakes

1. **Forgetting the `data.` prefix** when referencing.
2. **Filters that match nothing**, which gives an error like `no matching AMI found`. Debug the filter with the AWS CLI first.
3. **Filters that match several results** for singular sources like `aws_vpc`. Terraform errors with "multiple matches", so tighten the filter.
4. **Omitting `owners`** on `aws_ami`. Always set it.
5. **Using a data source for something Terraform itself manages in the same config.** If you create the VPC in this project, reference the resource directly (`aws_vpc.main.id`), and don't look it up with `data`.

---

## 8. Hands-on: see it with your own eyes

Check the AMI query with the AWS CLI so you see what Terraform sees:

```bash
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
            "Name=architecture,Values=x86_64" \
  --query 'sort_by(Images,&CreationDate)[-1].[ImageId,Name,CreationDate]' \
  --region us-east-1 \
  --output text
```

Then run:

```bash
terraform plan
```

and confirm the `ami` value in the plan matches what the CLI returned. They should agree.

After your first `apply`, try in `terraform console`:

```hcl
> data.aws_ami.al2023.id
> data.aws_ami.al2023.name
> data.aws_vpc.default.cidr_block
> data.aws_vpc.default.id
```

Explore what else the data source exposes with `terraform show`, or by reading the **Attributes Reference** section of the `aws_ami` page in the AWS provider docs. Learning to read those docs is a core Terraform skill, because every data source documents its **arguments** (what you give it) and its **attributes** (what you get back).

---

## Quick check

1. What is the difference between `aws_vpc.default.id` and `data.aws_vpc.default.id`? What does Terraform do if you write the first one?
2. Why is `owners = ["amazon"]` important in the AMI lookup?
3. Your teammate hardcodes `ami = "ami-0abc123"`. Name two problems this causes.
4. Does a `data` block ever create or delete anything in AWS?
5. Would you use a `data` block or a direct resource reference for an S3 bucket that **your own Terraform code creates**? Why?

Send me your answers. Once you're comfortable, continue with the S3 section of `main.tf` (the `random_id`, bucket, public access block, and versioning), where I'll explain why modern AWS provider versions split a bucket into several separate resources.