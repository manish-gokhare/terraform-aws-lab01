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