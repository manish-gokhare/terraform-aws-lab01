# Lesson 2: Variable Validation and HCL

It's a fair guess, but it isn't Python. The language is **HCL (HashiCorp Configuration Language)**, the same language as every other `.tf` file you've written. Validation has no separate language. The `condition` is an ordinary **HCL expression** that must evaluate to `true` or `false`.

---

## 1. Why it looks like Python

HCL expressions have function-call syntax (`name(args)`), so they resemble Python, JavaScript, and many other languages. But HCL is **declarative and not a general-purpose language**:

| Feature | Python | HCL |
|---|---|---|
| Loops / `if` statements | Yes | No (uses `for` expressions and `? :` instead) |
| Define your own functions | Yes | **No**, only built-in functions |
| Variables you reassign | Yes | No, values are fixed once evaluated |
| Purpose | Run instructions | Describe desired state |

You can only call the **built-in functions** Terraform ships with (`regex`, `can`, `contains`, `length`, `cidrhost`, and so on). You can't write your own.

---

## 2. Reading the block line by line

```hcl
validation {
  condition     = can(regex("^[a-z0-9-]{3,20}$", var.project_name))
  error_message = "project_name must be 3-20 characters: ..."
}
```

**`condition`** must return `true` (valid) or `false` (invalid). If it returns `false`, Terraform stops during `plan` and prints your `error_message`.

**`var.project_name`** is how HCL references the variable's value. Inside the validation block, it refers to the value the user supplied.

**`regex(pattern, string)`** is a built-in function that matches a string against a regular expression. Its behavior is the key to understanding this block:
- If the string **matches**, it returns the matched text.
- If it **doesn't match**, it throws an **error** (it does not return `false`).

**`can(expression)`** is a built-in function that fixes that. It evaluates the expression and returns:
- `true` if the expression succeeded without error
- `false` if the expression produced an error

So the logic chain is:

```
Input matches regex  →  regex() succeeds  →  can() returns true   →  valid
Input fails regex    →  regex() errors    →  can() returns false  →  error_message shown
```

`can()` converts "this call would crash" into a clean `false`. This `can(regex(...))` pattern is the standard idiom for validating strings in Terraform.

---

## 3. Decoding the regex: `^[a-z0-9-]{3,20}$`

The pattern uses RE2 regex syntax, which is the same flavor as in Go (Terraform is written in Go).

| Part | Meaning |
|---|---|
| `^` | Start of the string |
| `[a-z0-9-]` | One character: lowercase letter, digit, or hyphen |
| `{3,20}` | Repeat that between 3 and 20 times |
| `$` | End of the string |

The anchors `^` and `$` matter. Without them, `"UPPER-valid-name"` would still match, because the regex would find a valid *piece* inside it. With them, the **entire** string must fit the pattern.

---

## 4. Test it yourself: `terraform console`

`terraform console` is an interactive playground for HCL expressions. You can test any expression without deploying anything:

```bash
terraform console
```

```hcl
> regex("^[a-z0-9-]{3,20}$", "tflab")
"tflab"

> can(regex("^[a-z0-9-]{3,20}$", "tflab"))
true

> can(regex("^[a-z0-9-]{3,20}$", "TFLAB"))
false

> can(regex("^[a-z0-9-]{3,20}$", "ab"))
false

> can(regex("^[a-z0-9-]{3,20}$", "my_project"))
false
```

Type `exit` to leave. Make `terraform console` a regular habit for experimenting with functions.

---

## 5. Try it for real

```bash
terraform plan -var="project_name=MyProject"
```

You'll see an error like:

```
Error: Invalid value for variable

  on variables.tf line 8:
   8: variable "project_name" {
    var.project_name is "MyProject"

project_name must be 3-20 characters: lowercase letters, numbers, hyphens only (S3 naming rules).
```

This is Experiment #4 from the earlier plan. The error appears at **plan time**, before any AWS resource is touched.

---

## 6. Other validation patterns

All of these use only built-in functions and are worth knowing:

```hcl
# Value must be in an allowed list
condition = contains(["dev", "staging", "prod"], var.environment)

# Length check
condition = length(var.name) >= 3 && length(var.name) <= 20

# Number range
condition = var.volume_size >= 8 && var.volume_size <= 100

# Valid CIDR (the one used in your allowed_ssh_cidr variable)
condition = can(cidrhost(var.allowed_ssh_cidr, 0))

# Must start with a prefix
condition = startswith(var.bucket_name, "tflab-")
```

The `&&` (and), `||` (or), and `!` (not) operators work as you'd expect.

---

## 7. Why validate here and not later

| Without validation | With validation |
|---|---|
| Bad name fails midway through `apply` | Fails instantly at `plan` |
| Cryptic AWS API error | Your own clear message |
| Partial infrastructure may already exist | Nothing was created |

Validation is **fail-fast** design, and that's why it's a best practice.

---

## Quick check for you

Without running it, predict the result of each, then confirm in `terraform console`:

1. `can(regex("^[a-z0-9-]{3,20}$", "my-app-01"))`
2. `can(regex("^[a-z0-9-]{3,20}$", "this-name-is-way-too-long-for-us"))`
3. `can(regex("[a-z]+", "ABC123def"))` (note: no anchors)

Send me your predictions and what the console shows. Question 3 is the tricky one, and it tests whether you understood why the `^` and `$` anchors matter.
