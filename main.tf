provider "aws" {
  region = "eu-west-1"
}

################# EC2 ##################
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.nano"
  vpc_security_group_ids = [aws_security_group.allow_http.id]
  iam_instance_profile = aws_iam_instance_profile.test_profile.name
  subnet_id = aws_subnet.public.id
  user_data = <<EOF
#!/bin/bash
apt update
apt install nginx -y
echo "<h2>Web 1</h2>" > /var/www/html/index.html
systemctl restart nginx
EOF
  tags = {
    Name = "Web"

  }
}

resource "aws_eip" "lb" {
  instance = aws_instance.web.id
  vpc      = true
}

####################### VPC ########################

resource "aws_vpc" "myte" {
  cidr_block = "10.0.0.0/24"
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.myte.id
  map_public_ip_on_launch = true
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "eu-west-1a"
  tags = {
    Name = "Test"
  }
}

resource "aws_internet_gateway" "myte" {
  vpc_id = aws_vpc.myte.id

  tags = {
    Name = "main"
  }
}

resource "aws_default_route_table" "r" {
  default_route_table_id =  aws_vpc.myte.default_route_table_id
  

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myte.id
  }
}

resource "aws_security_group" "allow_http" {
    name = "allow_http"
    vpc_id = aws_vpc.myte.id


    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]

    }
    tags = {
        Name = "allow_http"
    }
}
####################### S3 #################
resource "aws_s3_bucket" "myte-web-res" {
  bucket = "myte-web-res"
  acl    = "public-read"
  website {
    index_document = "index.html"
    error_document = "error.html"
  }
  tags = {
    Name        = "My web"
  }
}


resource "aws_s3_bucket_object" "Screen" {
    bucket = aws_s3_bucket.myte-web-res.id
    acl    = "private"
    key    = "Screen.png"
    source = "./res/Screen.png"
}
resource "aws_s3_bucket_object" "index" {
    bucket = aws_s3_bucket.myte-web-res.id
    acl    = "private"
    key    = "index.html"
    source = "./res/index.html"
}

######################### IAM ######################
resource "aws_s3_bucket_policy" "b" {
  bucket = aws_s3_bucket.myte-web-res.id

  policy = data.aws_iam_policy_document.for_s3.json

}
data "aws_iam_policy_document" "for_s3" {
  statement {
    effect = "Allow"
    principals  { 
      type = "AWS"    
      identifiers = [ aws_iam_role.test_role.arn ]
    }
    actions = [ "s3:GetObject", "s3:DeleteObject"]
    resources = [
      "${aws_s3_bucket.myte-web-res.arn}/*"
    ]
  }
}

resource "aws_iam_role" "test_role" {
  name = "test_role"
  assume_role_policy = data.aws_iam_policy_document.for_ec2.json

  tags = {
      tag-key = "tag-value"
  }
}

data "aws_iam_policy_document" "for_ec2" {
  statement {
    effect = "Allow"
    actions = [ "sts:AssumeRole" ]
    principals  { 
      type = "Service"
      identifiers = ["ec2.amazonaws.com"] 
    }
  }
}


resource "aws_iam_instance_profile" "test_profile" {
  name = "test_profile"
  role = aws_iam_role.test_role.name
}

resource "aws_iam_role_policy" "test_policy" {
  name = "test_policy"
  role = aws_iam_role.test_role.id

  policy = data.aws_iam_policy_document.for_rol.json
}

data "aws_iam_policy_document" "for_rol" {
  statement {
    effect = "Allow"
    actions = [ "s3:GetObject","s3:DeleteObject"]
    resources = ["*"]
  }
}


resource "aws_iam_user" "github" {
  name = "github"
}

resource "aws_iam_access_key" "github" {
  user = aws_iam_user.github.name
}

resource "aws_iam_user_policy" "github" {
  name = "test"
  user = aws_iam_user.github.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Effect": "Allow",
      "Resource": "${aws_s3_bucket.myte-web-res.arn}/*"
    }
  ]
}
EOF
}

output "aws_iam_secret_key" {
  value = aws_iam_access_key.github.secret
  sensitive = true
}

output "aws_iam_access_key" {
  value = aws_iam_access_key.github.id
  sensitive = true
}
