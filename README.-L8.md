# Lesson 8 (Revised): Security Group Rules and Ports

I've added a dedicated section on `from_port` and `to_port` and rewritten the rest of the lesson around it.

---

## 1. The big idea: ports are doors

An IP address identifies the **building** (your server). A port identifies the **door** into that building. Each service listens on its own door:

| Port | Service |
|---|---|
| 22 | SSH |
| 80 | HTTP |
| 443 | HTTPS |
| 3306 | MySQL |
| 5432 | PostgreSQL |

A security group rule answers: **"Which doors are open, and to whom?"**

`from_port` and `to_port` define the **range of doors** the rule covers. Think of them as the first and last door number.

```
from_port = 22,  to_port = 22    →  only door 22
from_port = 8000, to_port = 8100 →  doors 8000, 8001, ... 8100 (101 doors)
```

---

## 2. The rules for `from_port` and `to_port`

| Protocol (`ip_protocol`) | `from_port` / `to_port` | Example |
|---|---|---|
| `"tcp"` or `"udp"` | Port range. Both set. | `22` / `22` |
| `"icmp"` | **Different meaning**: `from_port` = ICMP type, `to_port` = ICMP code | `8` / `-1` (ping) |
| `"-1"` (all protocols) | **Omit both.** Ports don't apply. | no ports |

### Case 1: One port (most common)

```hcl
from_port   = 22
to_port     = 22
ip_protocol = "tcp"
```

Same number on both sides means exactly one port.

### Case 2: A port range

```hcl
from_port   = 8000
to_port     = 8100
ip_protocol = "tcp"
```

Every port from 8000 to 8100 is open, so use ranges sparingly. A wider range means a bigger attack surface.

### Case 3: All TCP ports

```hcl
from_port   = 0
to_port     = 65535
ip_protocol = "tcp"
```

This is valid but rarely wise on ingress.

### Case 4: ICMP (ping), where the fields change meaning

```hcl
ip_protocol = "icmp"
from_port   = 8    # ICMP type 8 = echo request (ping)
to_port     = -1   # -1 = all ICMP codes
```

Here the numbers are **not ports**. They are the ICMP type and code. It's a quirk of the AWS API that reuses the same two fields. You'll rarely need it, but it explains why you sometimes see `-1` in a port field.

### Case 5: All traffic (your egress rule)

```hcl
ip_protocol = "-1"
# no from_port, no to_port
```

---

## 3. Gotchas

**Gotcha 1: a range is not a list.** To open ports 80 **and** 443, don't write this:

```hcl
from_port = 80
to_port   = 443   # opens EVERY port from 80 to 443 (364 ports!)
```

Create **two rules**, one for each port. This is the most common beginner mistake.

**Gotcha 2: `from_port` must be less than or equal to `to_port`.** Reversed values are rejected.

**Gotcha 3: forgetting ports with `tcp`.** If you set `ip_protocol = "tcp"` and leave out the ports, the rule is incomplete and the apply will fail. Protocol and ports go together.

**Gotcha 4: adding ports to `-1`.** With "all protocols" there's nothing to restrict, so leave them out.

---

## 3b. Reading your two rules line by line

### Ingress (traffic coming IN)

```hcl
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ssh.id
  description       = "SSH from allowed CIDR"
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
}
```

| Line | Meaning |
|---|---|
| `security_group_id` | Which security group owns this rule. Also creates the build-order dependency. |
| `description` | A console label. Optional but good practice. |
| `cidr_ipv4` | **Who** may connect (`/32` is one IP, `0.0.0.0/0` is everyone). |
| `from_port` / `to_port` | **Which door**: port 22 only. |
| `ip_protocol` | **Which language** the traffic speaks: TCP. |

Plain English: *"Allow TCP traffic on port 22 from this CIDR."*

A rule always has four parts: **who** (`cidr_ipv4`), **what protocol** (`ip_protocol`), **which door** (`from_port`/`to_port`), and **which group** (`security_group_id`).

### Egress (traffic going OUT)

```hcl
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ssh.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
```

Plain English: *"The instance may send any traffic, on any port, anywhere."* We define it explicitly because the AWS provider removes the default allow-all egress rule from groups it creates. Without it, the instance couldn't run package updates or reach S3.

**Stateful reminder:** the SSH ingress rule lets the connection in, and the replies go back out automatically. The egress rule covers connections the **instance starts**.

---

## 4. Why separate rule resources

Older code used inline `ingress {}` / `egress {}` blocks inside `aws_security_group`. That style can't tag rules individually, and mixing it with standalone rule resources makes Terraform fight itself. The provider docs now recommend standalone `aws_vpc_security_group_*_rule` resources. **Pick one style per group and never mix them.**

---

## 5. Production pattern: make the port a variable

Hardcoding `22` is fine for the lab. In production, make the door configurable and validated, which reuses Lessons 2 and 4:

```hcl
variable "ssh_port" {
  description = "Port to open for SSH"
  type        = number
  default     = 22

  validation {
    condition     = var.ssh_port >= 1 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1 and 65535."
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = var.allowed_ssh_cidr
  from_port         = var.ssh_port
  to_port           = var.ssh_port
  ip_protocol       = "tcp"
}
```

And for several ports (web server on 80 and 443), a preview of `for_each`, which is the next big lesson:

```hcl
locals {
  web_ports = toset([80, 443])
}

resource "aws_vpc_security_group_ingress_rule" "web" {
  for_each = local.web_ports

  security_group_id = aws_security_group.ssh.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
}
```

One block creates two rules, one per port, which avoids Gotcha 1.

---

## 6. Try it

**Experiment A: see the plan.** Run `terraform plan` and find:

```
+ from_port   = 22
+ to_port     = 22
+ ip_protocol = "tcp"
```

**Experiment B: break it on purpose.** Temporarily set `from_port = 100` and `to_port = 22`, then run `terraform plan` or `apply`, and read the error.

**Experiment C: verify in AWS after apply.** Add this output to `outputs.tf`:

```hcl
output "security_group_id" {
  value = aws_security_group.ssh.id
}
```

Then run:

```bash
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$(terraform output -raw security_group_id) \
  --region us-east-1
```

Compare `FromPort` and `ToPort` in the JSON with your code.

---

## Quick check

1. What do `from_port = 22` and `to_port = 22` mean together?
2. You write `from_port = 80`, `to_port = 443`. Which ports are opened, and what's the correct way to open only 80 and 443?
3. Why do we leave out the ports when `ip_protocol = "-1"`?
4. What do the same two fields mean when `ip_protocol = "icmp"`?
5. A rule has four parts. Name them and the argument for each.

Send me your answers, and tell me what the plan or the experiments showed. Then continue with the rest of `main.tf`.