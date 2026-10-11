# Lesson 6: Picking the Right VPC with a Data Block

With 4 VPCs, a vague data block fails. Terraform needs your filters to match **exactly one** VPC. If zero or several match, `plan` stops with an error. That's a safety feature, because it refuses to guess.

---

## 1. Step one: look before you write code

Always inspect what exists first, using the CLI:

```bash
aws ec2 describe-vpcs --region us-east-1 \
  --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Default:IsDefault,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

You'll see something like:

```
| ID            | CIDR        | Default | Name              |
| vpc-0a1...    | 172.31.0.0/16 | True  | None              |
| vpc-0b2...    | 10.0.0.0/16 | False   | company-shared    |
| vpc-0c3...    | 10.1.0.0/16 | False   | payments-prod     |
| vpc-0d4...    | 10.2.0.0/16 | False   | sandbox           |
```

Now decide **which attribute uniquely identifies the one you want**.

---

## 2. Five ways to select one VPC

**Option 1: By tag (the most common and recommended)**

```hcl
data "aws_vpc" "selected" {
  tags = {
    Name = "company-shared"
  }
}
```

Works across regions and accounts, as long as the team follows a tagging convention. Tags are the contract between teams.

**Option 2: By filter**

```hcl
data "aws_vpc" "selected" {
  filter {
    name   = "tag:Name"
    values = ["company-shared"]
  }
}
```

Equivalent to option 1, but `filter` can match on more fields (like `cidr-block`, `state`) and accepts multiple values.

**Option 3: By CIDR**

```hcl
data "aws_vpc" "selected" {
  cidr_block = "10.0.0.0/16"
}
```

Works, but CIDRs are less self-explanatory than names.

**Option 4: By the default flag** (what your lab uses)

```hcl
data "aws_vpc" "default" {
  default = true
}
```

Only one default VPC exists per region, so it's always unique.

**Option 5: By ID (a variable)**

```hcl
variable "vpc_id" {
  type = string
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}
```

The most explicit option. It's useful when the caller must make a deliberate choice, and you still get all the VPC's attributes (CIDR, etc.) from the data source.

---

## 3. Make the choice configurable (production pattern)

Don't hardcode the VPC name in the data block. Take it as a **variable**, and let the data block do the lookup:

```hcl
variable "vpc_name" {
  description = "Name tag of the VPC to deploy into"
  type        = string
}

data "aws_vpc" "selected" {
  tags = {
    Name = var.vpc_name
  }
}
```

Now `dev` can use `vpc_name = "sandbox"` and `prod` can use `vpc_name = "company-shared"`, with the same code. This combines three lessons: variables as inputs, a data block as a lookup, and interpolation.

---

## 4. Then find the subnets inside that VPC

```hcl
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }

  tags = {
    Tier = "private"
  }
}
```

Notice `data.aws_vpc.selected.id` feeds the second lookup. Data sources can depend on each other, and Terraform orders them automatically.

`aws_subnets` (plural) returns a **list of IDs** in `.ids`. Use one like this:

```hcl
resource "aws_instance" "web" {
  subnet_id = data.aws_subnets.private.ids[0]
}
```

---

## 5. What errors look like

| Problem | Error you'll see | Fix |
|---|---|---|
| Filter matches 0 VPCs | `no matching EC2 VPC found` | Check the tag value (case-sensitive) and the region |
| Filter matches 2+ VPCs | `multiple EC2 VPCs matched; use additional constraints` | Add another filter such as `cidr_block` |
| Wrong region | Same as 0 matches | Confirm the `provider "aws" { region = ... }` setting |

Remember the other validation idea from earlier: use a `validation` block on `vpc_name` if you want to fail even sooner on empty input.

---

## 6. Which option should you use?

| Situation | Best choice |
|---|---|
| Learning lab, just need something that works | `default = true` |
| Company with a tagging standard | Tag lookup via a variable |
| Highest safety, caller must be explicit | VPC ID variable |
| Network built in your *own* Terraform | Don't use `data` at all: reference `aws_vpc.main.id` directly (Lesson 5, mistake #5) |

**A caution about the default VPC in your lab:** with 4 VPCs, your lab's `default = true` lookup still works and picks the default one. But if the default VPC was **deleted** in your account (some companies do this), the lookup fails with "no matching VPC". In that case use a tag or ID lookup instead.

---

## 7. Try it now

1. Run the CLI command above to list your 4 VPCs.
2. Pick one and write a data block that selects it by **tag** (or by **ID** if it has no Name tag).
3. In `terraform console`, check that it resolved correctly:

```hcl
> data.aws_vpc.selected.id
> data.aws_vpc.selected.cidr_block
```

4. Deliberately break it: change the tag to something that doesn't exist and read the error.

---

## Quick check

1. Your filter matches 2 VPCs. What does Terraform do, and how do you fix it?
2. Why is selecting by a **tag** more portable than selecting by VPC ID?
3. Write a data block that selects the VPC whose CIDR is `10.1.0.0/16`.

Send me your answers, and tell me which of the 4 VPCs you chose and how you selected it. Then continue with the S3 section of `main.tf`.