# Lesson 7: What Does an EC2 Instance Need?

You don't have to memorize this. There's a method for finding it out, and a mental model that makes it easy to remember.

---

## 1. The mental model: EC2 is a rented computer

Imagine renting a computer in a data center. Ask yourself five questions:

| Question | AWS answer | Terraform argument |
|---|---|---|
| **What software** does it run? | An image (AMI) | `ami` |
| **How big** is it? | Instance type | `instance_type` |
| **Where** does it live? | Subnet inside a VPC | `subnet_id` (or the default VPC) |
| **Who can talk to it?** | Security group | `vpc_security_group_ids` |
| **Who is it?** (identity) | IAM role via instance profile | `iam_instance_profile` |

Plus one more, for logging in:

| **How do I log in?** | Key pair | `key_name` |

A memory trick: **"What, How big, Where, Who can reach it, Who is it, How do I log in."**

---

## 2. Required vs optional: the real answer

Only **two** arguments are truly required by Terraform for `aws_instance`:

```hcl
resource "aws_instance" "minimal" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"
}
```

That's valid. AWS fills in the rest with defaults: the default VPC, the default security group, no key pair, no IAM role. It works, but you can't SSH in, and it uses defaults you didn't choose.

Everything else is **optional in Terraform but required by your goal**. Your lab needs SSH access, so you add a key pair and a security group. It needs S3 access, so you add an IAM profile. **Requirements come from what you want the server to do, not from Terraform.**

---

## 3. The dependency picture

This is the easy way to remember what you build and in what order. Think of the instance as the **last** thing you create, and everything it needs as **ingredients** built first:

```
            ┌─ AMI (data) ───────────────┐
            ├─ Key pair ─────────────────┤
 Ingredients├─ Security group ── rules ──┼──►  EC2 instance
            ├─ IAM role ─ profile ───────┤
            └─ VPC / subnet (data) ──────┘
```

And that is exactly the order of your `main.tf`: data sources, key pair, security group, IAM, and then the instance. Terraform works out the order itself, because the instance **references** each ingredient.

---

## 4. Security group and rules: the relationship

This is probably the part that confuses you. Think of a **building with a security guard**:

- **Security group** = the guard's **rulebook** (an empty container, attached to the instance)
- **Rules** = the **lines in the rulebook**

```hcl
# The rulebook (container)
resource "aws_security_group" "ssh" {
  name   = "tflab-dev-ssh-sg"
  vpc_id = data.aws_vpc.default.id
}

# Line 1: who may come IN
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ssh.id   # ← "this line belongs to that rulebook"
  cidr_ipv4         = "YOUR_IP/32"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}

# Line 2: who may go OUT
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

The rules are separate resources that point back to the group with `security_group_id`. The EC2 instance then points to the **group**, never to the individual rules.

```
instance ──► security group ◄── ingress rule
                            ◄── egress rule
```

**Ingress = Incoming, Egress = Exiting.** (Both start with a letter that hints at the direction.)

Security groups are **stateful**: if you allow a request in, the reply is allowed out automatically.

---

## 5. How to find out what any resource needs (the real skill)

Never rely on memory alone. For **any** resource, use this routine:

**Step 1: Open the provider docs.** Search "terraform aws_instance" and open the page on registry.terraform.io.

**Step 2: Read the Argument Reference.** Required arguments are marked **(Required)**. Everything else is optional.

**Step 3: Read the Attribute Reference.** These are the values you can **get back** (like `id`, `arn`, `public_ip`), which you use to connect resources together.

**Step 4: Read the Example Usage at the top.** Copy the shape, then adapt it.

**Step 5: Let Terraform tell you.** Write what you know and run:

```bash
terraform validate
```

If a required argument is missing, you'll see:

```
Error: Missing required argument
  The argument "instance_type" is required, but no definition was found.
```

You can also check in the console without any docs:

```bash
terraform providers schema -json | jq '.provider_schemas[].resource_schemas["aws_instance"].block.attributes | keys'
```

(That last one needs `jq` installed and shows every argument.)

---

## 6. A cheat-sheet for your own use

Make this your own notes table:

| I want my server to... | I need to add |
|---|---|
| Exist at all | `ami`, `instance_type` |
| Be reachable on a port | Security group + ingress rule |
| Reach the internet | Egress rule (+ public IP or NAT) |
| Let me SSH in | Key pair (`key_name`) + port 22 rule |
| Call AWS APIs (S3, etc.) | IAM role → instance profile |
| Run a startup script | `user_data` |
| Have a bigger disk | `root_block_device` |
| Live in a specific network | `subnet_id` |

Before writing any infrastructure, ask: **"What does this need to do?"** Then add only the ingredients for those jobs.

---

## Quick check

1. Which two arguments does `aws_instance` strictly require?
2. In one sentence, what is the relationship between a security group and a security group rule?
3. Your instance must read files from S3. Which ingredient do you add, and which argument on the instance connects it?
4. Where in the provider docs do you find the values a resource gives back?

Send me your answers. When you're ready, continue with `main.tf`: the S3 section is next, followed by the key pair, security group, IAM, and finally the EC2 instance.