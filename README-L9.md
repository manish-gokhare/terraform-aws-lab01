# Lesson 10: Two Kinds of Data Sources

You caught a real inconsistency in how I taught this. In Lesson 5 I said a data block means "go look this up in the outside world." I did mention `aws_iam_policy_document` as a special exception, but I buried it in the use-cases list instead of making it a headline rule. Your confusion is justified, so let's fix it properly.

And one correction to your wording: that data block **does not create the policy in AWS**. It creates nothing anywhere. Here is why.

---

## 1. The refined definition

> A `data` block **produces a value for you to use**. It never creates or manages infrastructure.

Data sources come in two kinds:

| Kind | What it does | Talks to AWS? | Example |
|---|---|---|---|
| **Lookup** | Reads something that already exists | Yes | `aws_ami`, `aws_vpc`, `aws_caller_identity` |
| **Computation** | Calculates a value from the inputs you give it | **No** | `aws_iam_policy_document` |

My Lesson 5 definition ("read from the outside world") was accurate for the first kind only. The better, complete rule is: **a data block is read-only and creates nothing**.

---

## 2. What `aws_iam_policy_document` actually does

```hcl
data "aws_iam_policy_document" "s3_access" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.app.arn]
  }
}
```

This block is a **JSON formatter**. It takes your HCL and outputs a string. That's all. Prove it in `terraform console`:

```hcl
> data.aws_iam_policy_document.s3_access.json
```

You'll see plain JSON text like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::tflab-dev-data-ab12cd34"
    }
  ]
}
```

It's just text sitting in memory. Nothing exists in IAM yet.

---

## 3. Where the policy is actually created

Look at the **two-step pattern**:

```hcl
# STEP 1: DATA (computation): write the policy as JSON text. Creates NOTHING.
data "aws_iam_policy_document" "s3_access" {
  ...
}

# STEP 2: RESOURCE: this is what creates the policy in AWS.
resource "aws_iam_role_policy" "s3_access" {
  name   = "..."
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.s3_access.json   # ← feeds the text in
}
```

Analogy: the data block is **typing a letter in a word processor**. The resource is **posting it**. Typing alone delivers nothing.

| Block | Creates something in AWS? |
|---|---|
| `data.aws_iam_policy_document` | **No** |
| `aws_iam_role_policy` | **Yes**, this makes the policy real |

You can confirm it after `apply`: `terraform state list` shows the data source with a `data.` prefix, but only the `resource` entries correspond to real AWS objects.

---

## 3b. Why not just write the JSON by hand?

You can. This does the same job:

```hcl
resource "aws_iam_role_policy" "s3_access" {
  name = "..."
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:ListBucket"]
      Resource = aws_s3_bucket.app.arn
    }]
  })
}
```

Both `jsonencode()` and the policy-document data source are valid. The data source gives you validation of the policy structure, merging of several documents, and readable `statement` blocks. Teams pick one style and stay consistent.

---

## 4. Another computation example: `aws_iam_policy_document` is not alone

Other data sources that calculate instead of look up:

```hcl
data "aws_partition" "current" {}          # tells you "aws" vs "aws-cn", from the provider config
data "template_file" ...                    # legacy, avoid
data "external" "x" { program = [...] }     # runs a script and returns its output
```

So the rule of thumb for deciding whether a data source touches AWS is to read its page in the provider docs. If the arguments are filters (name, tags, ID), it's a lookup. If the arguments describe content you're writing (statements, actions), it's a computation.

---

## 5. The decision flow

```
Does this block CREATE or CHANGE something in AWS?
        │
        ├─ Yes ──► resource
        │
        └─ No ──► data
                     │
                     ├─ Looks up an existing thing ──► lookup data source
                     └─ Just formats/calculates a value ──► computation data source
```

---

## Quick check

1. Does `data "aws_iam_policy_document"` create a policy in IAM? What does it produce?
2. Which block in the lab actually makes the permissions real in AWS?
3. Is `data.aws_ami.al2023` a lookup or a computation data source? What about `data.aws_iam_policy_document.ec2_assume_role`?
4. Complete the sentence: "A data block never ______, it only ______."

Send me your answers. Then finish the last block of `main.tf` (the EC2 instance) and you can start running `init`, `fmt`, `validate`, `plan`.