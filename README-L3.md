# Lesson 4: `locals` vs `variables`

They look similar because both are referenced by name, but they play opposite roles.

> **Variables are the inputs to your configuration. Locals are the internal calculations inside it.**

If you know programming, the analogy is a function: `variable` is a **function parameter** (the caller supplies it), and `locals` are **local variables** inside the function body (the function computes them for itself).

---

## 1. The key differences

| | `variable` | `locals` |
|---|---|---|
| Purpose | Accept input from outside | Compute and name values internally |
| Who sets the value | The user (CLI, tfvars, env var, prompt) | Only the code itself |
| Can the user override it? | Yes | **No** |
| Can it reference other things? | No (only a static `default`) | **Yes**: variables, resources, data sources, other locals, functions |
| Has `type`, `validation`, `description`? | Yes | No |
| Referenced as | `var.name` | `local.name` (**singular**) |

Notice the syntax: the block is `locals` (plural), but you reference a value as `local.name_prefix` (singular). It's a very common typo.

The row to remember is "can it reference other things?" A `default` can't say `default = "${var.project_name}-${var.environment}"`. Terraform rejects variables that refer to other variables. Locals exist to fill that gap.

---

## 2. When to use a local

**Use a variable when** a human or pipeline should be able to choose the value: region, instance type, environment, CIDR ranges, feature toggles.

**Use a local when** the value is **derived** or **repeated** and nobody should override it.

### Reason 1: DRY (Don't Repeat Yourself)

Without locals, the naming expression is repeated everywhere:

```hcl
resource "aws_s3_bucket" "app" {
  bucket = "${var.project_name}-${var.environment}-data"
}
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"
}
```

Change your naming convention and you have to hunt through 30 places. With a local, you change **one line**:

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}
```

### Reason 2: Computed values from other resources or data

```hcl
locals {
  # derived from a data source: impossible in a variable default
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  # derived from a resource
  bucket_arn_wildcard = "${aws_s3_bucket.app.arn}/*"
}
```

### Reason 3: Readability: give complex expressions a name

```hcl
locals {
  is_prod            = var.environment == "prod"
  instance_count     = local.is_prod ? 3 : 1
  enable_monitoring  = local.is_prod
  backup_retention   = local.is_prod ? 30 : 7
}
```

Compare `count = local.is_prod ? 3 : 1` scattered everywhere with a named, documented decision in one place. Anyone reading `if local.is_prod` immediately understands the intent.

### Reason 4: Merging and transforming data

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # combine base tags with extra tags the caller supplied
  all_tags = merge(local.common_tags, var.extra_tags)
}
```

`merge()` can't be done in a variable default, but it's trivial in a local.

---

## 3. Production patterns

**Pattern 1: Naming conventions in one place**
```hcl
locals {
  name_prefix = "${var.company}-${var.project_name}-${var.environment}"
}
```
This is the single most common local in real codebases.

**Pattern 2: Environment-specific settings from one lookup map**
```hcl
variable "environment" {
  type = string
}

locals {
  env_config = {
    dev = {
      instance_type = "t3.micro"
      min_size      = 1
      multi_az      = false
    }
    prod = {
      instance_type = "m6i.large"
      min_size      = 3
      multi_az      = true
    }
  }

  # pick the right block for the current environment
  config = local.env_config[var.environment]
}

resource "aws_instance" "web" {
  instance_type = local.config.instance_type
}
```
One variable (`environment`) drives many settings, and all the sizing decisions live in one reviewable table.

**Pattern 3: Prepare data for `for_each` (coming in a later lesson)**
```hcl
locals {
  subnets = {
    public-a  = { cidr = "10.0.1.0/24", az = "us-east-1a" }
    public-b  = { cidr = "10.0.2.0/24", az = "us-east-1b" }
  }
}
```

**Pattern 4: Turning messy input into clean data**
```hcl
locals {
  clean_name = lower(trimspace(var.raw_name))
}
```

---

## 4. Rules and gotchas

1. **Locals can reference each other**, but not circularly. `a = local.b` and `b = local.a` is an error.
2. **Locals have no `type`.** Terraform infers it. If you need strict typing, use a variable.
3. **Don't overuse them.** A local used exactly once, with a trivial expression, adds indirection for no benefit. A good rule: create a local when a value is **used 2 or more times**, or when naming it makes a complex expression **easier to understand**.
4. **Don't use a local when a user needs control.** If a team might legitimately want a different value, make it a variable (with a sensible default).
5. **They can be defined in any `.tf` file** in the directory and used anywhere in the same module. Locals are **module-scoped**, so a local in your root can't be seen from a child module.
6. **Multiple `locals` blocks are allowed.** Many teams group them by theme (`locals { naming }`, `locals { tags }`).

---

## 5. Walking through your own block

```hcl
locals {
  name_prefix = "${var.project_name}-${var.environment}"
```
Derived from two variables. Used in names of the bucket, role, key pair, security group, and EC2 instance. Nobody should override this directly. They change the two inputs instead.

```hcl
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
```
A map built from variables plus a fixed string. It feeds `default_tags` in `providers.tf`.

**The consequence of this design:** you change `environment` from `dev` to `prod` once, and every name and every tag follows. That's the whole point.

---

## 6. Try it in the console

Once `locals` is saved and you've run `terraform init`:

```bash
terraform console
```

```hcl
> local.name_prefix
"tflab-dev"

> local.common_tags
{
  "Environment" = "dev"
  "ManagedBy" = "Terraform"
  "Project" = "tflab"
}

> merge(local.common_tags, { Owner = "student" })
```

Now try overriding it from the CLI to see that **locals can't be set from outside**:

```bash
terraform plan -var="name_prefix=hello"
```

You'll get an error saying no variable named `name_prefix` is declared. That's the proof that locals are not inputs.

---

## Quick check

1. Why can't you write `default = "${var.project_name}-${var.environment}"` in a variable block?
2. You want users to choose between `dev` and `prod`, and you want `prod` to automatically use 3 instances. Which part is a `variable` and which is a `local`?
3. What's wrong with `var.name_prefix` if `name_prefix` is defined in `locals`?

Send me your answers. When you're done, continue with the rest of `main.tf`: the data sources (AMI and VPC) come next, and I'll explain how `data` blocks differ from `resource` blocks when you get there.